# irsa_demo

These are the things the script performs:
1. Create an IAM service account [2] using eksctl
2. Associates the following IAM Policy to the IAM service account - "arn:aws:iam::aws:policy/AmazonS3FullAccess"
3. Create a test S3 bucket
4. Create a Ubuntu Deployment.
5. The Pod created as a part of the Ubuntu deployment goes through the following steps:
=> Install "curl", "python", "jq", "pip" and "aws-cli" , which are prerequisites.
=> Run: $aws sts get-caller-identity . This command outputs the role that aws-cli would be using to make API calls on your behalf.
=> Downloads s3-echoer [3] executable for write test files to the S3 bucket
=> Lists all the objects within the S3 bucket
6. Once the Deployment is created, you can check the logs of the Pod to examine the output of the commands: $kubectl logs -f <pod_name>

The script accepts the Region and the EKS Cluster name as script parameters. 
For ex: bash IRSA_demo_access_s3.sh us-east-1 my-first-cluster

Pre-requisites for the script:
1. EC2 Instance/Workstation that has access to the AWS Account and permissions to be able to make AWS API calls and access the EKS Cluster.
2. Has "eksctl", "aws cli" and "kubectl" utilities installed
3. Is a Linux based machine

References:
[1] https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/
[2] Creating an IAM Role and Policy for your Service Account  - Create an IAM Role - https://docs.aws.amazon.com/eks/latest/userguide/create-service-account-iam-policy-and-role.html#create-service-account-iam-role
[3] s3-echoer - https://github.com/mhausenblas/s3-echoer

