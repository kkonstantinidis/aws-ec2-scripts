#Script createec2.sh should run first
#Master and all slaves should be running 

#Read the AWS parameters of your cluster from file lines
publicKey=$(sed '4!d' "awsconf.txt")
username=$(sed '5!d' "awsconf.txt")

#Ask Amazon CLI for your hostnames, remove the line that contains the word "None", remove empty lines, replace the "Name\t" with '' (parameters in "sed" command are separated with '/', 's' means replace, next is what to replace i.e "Name\t", next is with what i.e. '' and next are the flags), combine every 2 consecutive lines by leaving a space between their contents (the basic difference here is the "N;" which stands for next so here it goes to the end of the first line and removes the "\n" and so on). Finally, remove the empty lines (terminated instances that still show up) and save to a txt file.
aws ec2 describe-instances --query "Reservations[*].Instances[*].[PublicDnsName,Tags]" --output=text | grep -vwE "None" | sed 's/Name\t//g' | sed 'N;s/\n/ /' | grep -v -e '^[[:space:]]*$' > 'ec2instances.txt';

#Remove any preexisting SSH configuration file
if [ -f config ]; then
    rm config
fi
touch config

while read line
do
    #Read the line, keep the 1st word and save it as the public DNS
    publicDns=$(echo "$line" | cut -d " " -f1);

    #Read the line, keep the 2nd word and save it as the hostname you will be using locally to connect to your Amazon EC2
    instanceHostname=$(echo "$line" | cut -d " " -f2);

    #OK, we are now ready to store to SSH known hosts
    sshEntry="Host $instanceHostname\n";
    sshEntry="$sshEntry HostName $publicDns\n";
    sshEntry="$sshEntry User $username\n";
    sshEntry="$sshEntry IdentityFile ~/.ssh/$publicKey\n";

    #Attach to the EOF, '-e' enables interpretation of backslash escapes
    echo -e "$sshEntry" >> config

#Below is the txt file you will be traversing in the loop
done < ec2instances.txt

#Done
rm ~/.ssh/config
mv config ~/.ssh/config
rm ec2instances.txt
