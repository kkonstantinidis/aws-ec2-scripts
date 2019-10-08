#Set the AWS parameters of your cluster
AWSAccessKeyId="";
AWSSecretKey="";
AWSregion="us-east-1";

#Change the following variables based on your cluster's public SSH key (assumed common for all nodes) and the default username (-//-)
publicKey="virginiakey";
username="ubuntu";

#Save parameters to files for other scripts to get
echo $AWSAccessKeyId > awsconf.txt
echo $AWSSecretKey >> awsconf.txt
echo $AWSregion >> awsconf.txt
echo $publicKey".pem" >> awsconf.txt
echo $username >> awsconf.txt

#The prefix that the master's "Name" tag should have. Maybe there will be a problem if you set tag key other than "Name"
#masterHostname="mpi_master";
masterHostname="t2_master";
#masterHostname="t2_master_bench";
echo $masterHostname >> awsconf.txt

#The prefix that the slaves' "Name" tag should have. Maybe there will be a problem if you set tag key other than "Name"
slavePrefix="slave";
echo $slavePrefix >> awsconf.txt

#You will need to be root for some functions
rootname="root";
echo $rootname >> awsconf.txt

#Master's AMI name
masterAmi="mpi_master_ami"
#masterAmi="mpi_master_slave_ami"
#masterAmi="mpi_enhanced_master_ami"

#Slaves' AMI name
slaveAmi="mpi_slave_ami"
#slaveAmi="mpi_master_slave_ami"
#slaveAmi="mpi_enhanced_slave_ami"

#MPI EC2 instances security group name
securityGroup="mpi_security"

#Subnet ID for the cluster like us-east-1c for all instances to avoid charges
subnetId="subnet-c739ac8f"

#Instance type
#masterEc2="m5d.12xlarge"
#masterEc2="r5d.2xlarge"
masterEc2="x1e.2xlarge"
#masterEc2="r3.large"
#masterEc2="m4.large"
#masterEc2="t2.micro"
#masterEc2="c1.medium"
#slaveEc2="c3.8xlarge"
#slaveEc2="m3.large"
#slaveEc2="c3.large"
#slaveEc2="r4.2xlarge"
slaveEc2="m1.medium"
#slaveEc2="m4.large"
#slaveEc2="t2.micro"
#slaveEc2="r3.large"
#slaveEc2="r4.large"

#The name of the EC placement group that the created slaves you want to belong to (requires compatible instance types)
pgname="cdc_cluster"

#Configure AWS
aws configure set aws_access_key_id $AWSAccessKeyId
aws configure set aws_secret_access_key $AWSSecretKey
aws configure set default.region $AWSregion

#Ask the user whether he merely wants to reconfigure the cluster
read -p "Amazon CLI configured. Do you also want to create a new MPI cluster (configuration for Virginia is needed) (y/n)? " CONT
if [ "$CONT" = "n" ]; then
    echo "Exiting...";
    exit 0
fi

#Read from user
echo "Enter the desired number of masters [max=1]: "
read mastersNo
while [ $mastersNo -ge 2 ]
do
    echo "Error: At most 1 master is allowed."
    echo "Enter the desired number of masters [max=1]: "
    read mastersNo
done
echo "Enter the desired number of slaves [max=40]: "
read slavesNo
while [ $slavesNo -ge 41 ]
do
    echo "Error At most 19 slaves are allowed."
    echo "Enter the desired number of slaves [max=40]: "
    read slavesNo
done

read -p "Do you want to use the placement group (m4.large instances are needed) (y/n)? " pg

#Check whether security group $securityGroup exist otherwise create and configure it. "-q" is for quiet
if aws ec2 describe-security-groups --filters Name=group-name,Values=$securityGroup | grep -q $securityGroup
then 

    echo "Security settings exist."
    aws ec2 describe-security-groups --filters Name=group-name,Values=$securityGroup --query 'SecurityGroups[*].{ID:GroupId}' > securityGroupId.txt

else

    echo "New security settings will be created."

    #The command outputs the ID of the newly created key and we need to keep that
    aws ec2 create-security-group --group-name $securityGroup --description "mpi" > securityGroupId.txt

    #Read security group ID from file
    securityGroupId=$(sed '1!d' "securityGroupId.txt")
	
    #Configure ingress start of port range for the TCP and UDP protocols (-1 for every port and protocol), IP range (-1 for everything) and similarly for IPv6
    aws ec2 authorize-security-group-ingress --group-id $securityGroupId --ip-permissions FromPort=-1,IpProtocol=-1,IpRanges=[{CidrIp="0.0.0.0/0"}],Ipv6Ranges=[{CidrIpv6="::/0"}]

    #SImilarly for egress
    aws ec2 authorize-security-group-egress --group-id $securityGroupId --ip-permissions FromPort=-1,IpProtocol=-1
fi

#Get the ID of master's AMI assuming it's unique
aws ec2 describe-images --filters Name=name,Values=$masterAmi --query 'Images[*].{ID:ImageId}' --output text > masterAmiId.txt

#Read master AMI ID
masterAmiId=$(sed '1!d' "masterAmiId.txt")

#Same for slave
aws ec2 describe-images --filters Name=name,Values=$slaveAmi --query 'Images[*].{ID:ImageId}' --output text > slaveAmiId.txt
slaveAmiId=$(sed '1!d' "slaveAmiId.txt")

securityGroupId=$(sed '1!d' "securityGroupId.txt")

#Create master EC2
count=1
while [ $count -le $mastersNo ]
do
    

    if [ "$pg" = "y" ]; then

        #Use placement group
        aws ec2 run-instances --image-id $masterAmiId --count 1 --instance-type $masterEc2 --key-name $publicKey --security-group-ids $securityGroupId --placement GroupName=$pgname --subnet-id $subnetId --tag-specifications  "ResourceType=instance,Tags=[{Key=Name,Value=$masterHostname}]"

    else

        #Do not use placement group
        aws ec2 run-instances --image-id $masterAmiId --count 1 --instance-type $masterEc2 --key-name $publicKey --security-group-ids $securityGroupId --subnet-id $subnetId --tag-specifications  "ResourceType=instance,Tags=[{Key=Name,Value=$masterHostname}]"

    fi

    (( count++ ))
done

#Create slaves EC2
count2=1
while [ $count2 -le $slavesNo ]
do

    if [ "$pg" = "y" ]; then

        #Use placement group
        aws ec2 run-instances --image-id $slaveAmiId --count 1 --instance-type $slaveEc2 --key-name $publicKey --security-group-ids $securityGroupId --placement GroupName=$pgname --subnet-id $subnetId --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$slavePrefix$count2}]"

    else

        #Do not use placement group
        aws ec2 run-instances --image-id $slaveAmiId --count 1 --instance-type $slaveEc2 --key-name $publicKey --security-group-ids $securityGroupId --subnet-id $subnetId --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$slavePrefix$count2}]"

    fi

    (( count2++ ))
done

#Done
rm securityGroupId.txt
rm masterAmiId.txt
rm slaveAmiId.txt

