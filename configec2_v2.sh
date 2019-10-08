#Script resolveec2.sh should run first, but it's executed here within the code
#Version 2 of configec2.sh tries to speed some things up and establish passwordless SSH from every slave to every other slave
#Script resolveec2.sh should run first so that we have the master's public hostname. No need to care about SSH to the master if you have followed the instructions section 17 for the AMIs
#Maybe after this script you need to reboot the slaves for the NFS to auto-mount, maybe mount it now within the script which is what I did
#Comment the NFS alternative code and uncomment the NFS code if you will be using NFS

#Ask the user whether he wants password-less SSH from each slave to each other slave
read -p "Do you also need password-less SSH from each slave to each other slave (y/n)? " slave_slave_SSH

#Convenient to resolve here
./resolveec2.sh

#Read the AWS parameters of your cluster from file lines. Whenever we don't specify username $username will be used
publicKey=$(sed '4!d' "awsconf.txt")
username=$(sed '5!d' "awsconf.txt")
masterHostname=$(sed '6!d' "awsconf.txt")
slavePrefix=$(sed '7!d' "awsconf.txt")
rootname=$(sed '8!d' "awsconf.txt")

#Ask Amazon CLI for the private hostnames of the coordinator and the slaves, remove the line that contains the word "None", combine every 2 consecutive lines by leaving a space between their contents (the basic difference with the next "sed" command is the "N;" which stands for "next" so here it goes to the end of the first line and removes the "\n" and so on), keep the lines that contain the predefined slave prefix, replace the "Name\t" with '' (parameters in "sed" command are separated with '/', 's' means replace, next is what to replace i.e. "Name\t", next is with what i.e. '' and next are the flags). Finally, remove the empty lines (terminated instances that still show up) and save to a txt file
aws ec2 describe-instances --query "Reservations[*].Instances[*].[PrivateDnsName,Tags]" --output=text | grep -vwE "None" | sed 'N;s/\n/ /' | grep -E $slavePrefix | sed 's/Name\t//g' | grep -v -e '^[[:space:]]*$' > 'mpi_slaves.txt';

#Create a similar file with only the slaves' tags. Also sort them so that they are assigned MPI ranks based on their name but numerically i.e. set "slave1" before "slave10".
aws ec2 describe-instances --query "Reservations[*].Instances[*].[Tags]" --output=text | grep -vwE "None" | grep -E $slavePrefix | sed 's/Name\t//g' | grep -v -e '^[[:space:]]*$' | sort --version-sort > 'mpi_slaves_tags.txt';

#But master is also an MPI process needed for the SSH config file and the MPI hostfile (but took care of it below) so attach it 
cp mpi_slaves.txt mpi_world.txt
aws ec2 describe-instances --query "Reservations[*].Instances[*].[PrivateDnsName,Tags]" --output=text | grep -vwE "None" | sed 'N;s/\n/ /' | grep -E $masterHostname | sed 's/Name\t//g' | grep -v -e '^[[:space:]]*$' >> 'mpi_world.txt';

#Remove any preexisting SSH configuration file and create a new one
if [ -f config ]; then
    rm config
fi
touch config

while read line
do
    #Read the line, keep the 1st word and save it as the private DNS
    privateDns=$(echo "$line" | cut -d " " -f1);

    #Read the line, keep the 2nd word and save it as the hostname you will be using locally to connect to your Amazon EC2
    instanceHostname=$(echo "$line" | cut -d " " -f2);

    #OK, we are now ready to store to SSH known hosts
    sshEntry="Host $instanceHostname\n";
    sshEntry="$sshEntry HostName $privateDns\n";
    sshEntry="$sshEntry User $username\n";
    sshEntry="$sshEntry IdentityFile ~/.ssh/$publicKey\n";

    #Attach to the EOF, '-e' enables interpretation of backslash escapes
    echo -e "$sshEntry" >> config

#Below is the txt file you will be traversing in the loop
done < mpi_world.txt

#Duplicate the file to read the nodes from in the loop
cp mpi_slaves_tags.txt mpi_slaves_tags_cpy.txt

#Copy SSH config to master
scp config $masterHostname:~/.ssh

#Generate SSH key on master. The following command will create 2 files but first delete any previous ones. As for ssh-keygen it automates the process by providing the output file  ("-f"), the type of they key ("rsa") and the passphrase ("") instead of pressing Enter 3 times 
ssh $username@$masterHostname "rm ~/.ssh/id_rsa*; ssh-keygen -f ~/.ssh/id_rsa -t rsa -N \"\""

#We need to provide root access to the master (writing is allowed for "/root/.ssh/" but we also need write permissions for other folders). The "-t" allows a temporary ssh connection to execute sudo
ssh -t $username@$masterHostname "sudo cp -rf /home/ubuntu/.ssh/authorized_keys /root/.ssh/"

#Remove previous configuration of MPI hostfile but suppress output after reading each line (-n) and keep comments starting ('^') with '#' and finally print the output
#Insert the MPI master in MPI hostfile
ssh $rootname@$masterHostname "cat /etc/openmpi/openmpi-default-hostfile | sed -n '/^#/p' > /etc/openmpi/openmpi-default-hostfile-tmp; echo \"$masterHostname slots=1\" >> /etc/openmpi/openmpi-default-hostfile-tmp"

#ctrOuter = 1

while read lineOuter
do

    echo -e "\nStarted configuration of $lineOuter... \n"

    scp config $lineOuter:~/.ssh

    #We need "-n" to redirects stdin from /dev/null (actually, prevents SSH from reading from stdin and consuming the whole file in the 1st iteration)
    ssh -n $username@$lineOuter "rm ~/.ssh/id_rsa*; ssh-keygen -f ~/.ssh/id_rsa -t rsa -N \"\""

    #Get the master password-less access to each slave. The following commands do not need root SSH
    ssh -n $username@$masterHostname "cat .ssh/id_rsa.pub | ssh $username@$lineOuter \"cat >> .ssh/authorized_keys\"; ssh $username@$lineOuter \"chmod 700 .ssh; chmod 640 .ssh/authorized_keys\""

    #Now we also need root access from master to slaves.  
    #Take root access to current slave. Double "-t" is needed here due to an error due to sudo inside an SSH command which demands a separate terminal and in this case stdin is not a terminal.
    ssh -n $username@$masterHostname "ssh -t -t $username@$lineOuter \"sudo cp -rf /home/ubuntu/.ssh/authorized_keys /root/.ssh/\""

    ssh -n $rootname@$lineOuter "cat /etc/openmpi/openmpi-default-hostfile | sed -n '/^#/p' > /etc/openmpi/openmpi-default-hostfile-tmp; echo \"$lineOuter slots=1\" >> /etc/openmpi/openmpi-default-hostfile-tmp"

    #Insert the MPI slaves in MPI hostfile. Add current slave to MPI hostfile.
    ssh -n $rootname@$masterHostname "echo "$lineOuter slots=1" >> /etc/openmpi/openmpi-default-hostfile-tmp"

    #ctrInner = 1

    if [ "$slave_slave_SSH" = "y" ]; then

        #Get the slave password-less access to each other slave. Insert the MPI slaves in each MPI hostfile.
        while read lineInner
        do

            #Assuming that the MPI broadcast tree assigns larger ranks to lower levels, we establish SSH and add MPI hostnames only of the slaves that will get higher ranks
            #if [ "$ctrInner" -le "$ctrOuter" ];
            #then
            #     ctrInner= $((ctrInner+1))
            #     continue
            #fi

            ssh -n $username@$lineOuter "cat .ssh/id_rsa.pub | ssh $username@$lineInner \"cat >> .ssh/authorized_keys\"; ssh $username@$lineInner \"chmod 700 .ssh; chmod 640 .ssh/authorized_keys\""

            ssh -n $rootname@$lineOuter "echo "$lineInner slots=1" >> /etc/openmpi/openmpi-default-hostfile-tmp"

        done < mpi_slaves_tags_cpy.txt 

    fi

    #Copy temporary file to the original and then delete it
    ssh -n $rootname@$lineOuter "cat /etc/openmpi/openmpi-default-hostfile-tmp > /etc/openmpi/openmpi-default-hostfile; rm /etc/openmpi/openmpi-default-hostfile-tmp"

    #ctrOuter= $((ctrOuter+1))

done < mpi_slaves_tags.txt 

ssh -n $rootname@$masterHostname "cat /etc/openmpi/openmpi-default-hostfile-tmp > /etc/openmpi/openmpi-default-hostfile; rm /etc/openmpi/openmpi-default-hostfile-tmp"

#Done
rm mpi_slaves.txt
rm mpi_slaves_tags.txt
rm mpi_slaves_tags_cpy.txt
rm mpi_world.txt

