#Destroys all MPI slave EC2 instances but not master. YOU HAVE TO MANUALLY DELETE MASTER'S TAG THOUGH

#Read the AWS parameters of your cluster from file lines
masterHostname=$(sed '6!d' "awsconf.txt")
slavePrefix=$(sed '7!d' "awsconf.txt")

echo "All slaves will be terminated."
read -p "Do you also want to change the master's tag (y/n) (you have to manually terminate master EC2): " changeTag

#Get the master's ID and change his tag only if he still exists
if [[ "$changeTag" = "y" && $(aws ec2 describe-instances --filters "Name=tag:Name,Values="$masterHostname"" --query "Reservations[*].Instances[*].[InstanceId]") ]];
then

    aws ec2 describe-instances --filters "Name=tag:Name,Values="$masterHostname"" --query "Reservations[*].Instances[*].[InstanceId]" > mpi_master_Id.txt
    mpi_master_Id=$(sed '1!d' "mpi_master_Id.txt")

    #Change master's tag
    date > dateNow.txt
    dateNow=$(sed '1!d' "dateNow.txt")
    aws ec2 create-tags --resources $mpi_master_Id --tags Key=Name,Value="mpi_prev_master$dateNow"

fi

#Get the slaves' IDs
aws ec2 describe-instances --filters "Name=tag:Name,Values="$slavePrefix*"" --query "Reservations[*].Instances[*].[InstanceId]" > mpi_slaves_Ids.txt 

#Destroy
while read line
do

    #Remove tag 
    aws ec2 delete-tags --resources $line

    #Terminate
    aws ec2 terminate-instances --instance-ids $line

done < mpi_slaves_Ids.txt

#Done
rm mpi_master_Id.txt
rm dateNow.txt
rm mpi_slaves_Ids.txt 
