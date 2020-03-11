## Source
# 1. https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/

# Required Variables
region=$1
clusterName=$2

[[ -z "$region" || -z "$clusterName" ]] && echo "Assign region and clusterName variables to something :/  Eg: steps.sh us-east-1 demo-cluster" && exit 0

# Optional - Change me to use non-defaul values
serviceAccountName="my-serviceaccount"
policyARN="arn:aws:iam::aws:policy/AmazonS3FullAccess"

# Check if eksctl, awsCli and kubectl exist
[[ ! `eksctl --help` ]] && echo "eksctl does not exist. Please install it first" && exit 1
[[ ! `kubectl --help` ]] && echo "eksctl does not exist. Please install it first" && exit 1
[[ ! `aws help` ]] && echo "eksctl does not exist. Please install it first" && exit 1

# Check Kubernetes Version
requiredK8sVersion="113"
K8sVersion=$(eksctl get cluster --name $clusterName | cut -f 2 | tr -d "\n" | tr -d ".")
[[ $K8sVersion -lt $requiredK8sVersion ]] && echo "Need Kubernetes Version 1.13 or greater..Exiting" && exit 1

# Check Eksctl Version
requiredEksctlVersion="050"
EksctlVersion=$(eksctl version | awk -F ':"' '{print $4}' | sed 's/[^a-zA-Z0-9]//g')
[[ $EksctlVersion -lt $requiredEksctlVersion ]] && echo "Need eksctl Version greater than 0.5.0 ..Exiting" && exit 1

# Associate OIDC
eksctl utils associate-iam-oidc-provider --name $clusterName --approve

# Create Service account
eksctl create iamserviceaccount --name $serviceAccountName --namespace default --cluster $clusterName --attach-policy-arn $policyARN --approve

RoleARN=$(kubectl get sa $serviceAccountName -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role\-arn}')
TARGET_BUCKET="${clusterName}-test-2020"

# Create a test bucket
echo "Creating a test bucket: $TARGET_BUCKET"
if [ $region == "us-east-1" ]
then
aws s3api create-bucket --bucket $TARGET_BUCKET --region $region
else
aws s3api create-bucket --bucket $TARGET_BUCKET --region $region --create-bucket-configuration LocationConstraint=$region 
fi

# Create an Ubuntu Deployment
cat > ubuntu-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ubuntu-deployment
spec:
  selector:
    matchLabels:
      app: ubuntu
  replicas: 1
  template:
    metadata:
      labels:
        app: ubuntu
    spec:
      serviceAccountName: ${serviceAccountName}
      containers:
      - name: ubuntu
        image: ubuntu:latest
        command: ["/bin/sh","-c"]
        args:
          - apt-get -qq update && apt-get -qq install curl python -y && \
            curl https://stedolan.github.io/jq/download/linux64/jq > /usr/bin/jq && chmod +x /usr/bin/jq && \
            curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python get-pip.py && \
            pip install awscli --upgrade && \
            aws sts get-caller-identity --region $region && \
            curl -sL -o /s3-echoer https://github.com/mhausenblas/s3-echoer/releases/latest/download/s3-echoer-linux && chmod +x /s3-echoer && echo This is an in-cluster test | /s3-echoer ${TARGET_BUCKET} && \
            aws s3api list-objects --bucket $TARGET_BUCKET && \
            echo "sleeping for 10 hours" && \
            sleep 10h
        env:
        - name: AWS_DEFAULT_REGION
          value: "${region}"
        - name: ENABLE_IRP
          value: "true"
EOF

# Create a deployment
kubectl apply -f ubuntu-deployment.yaml
sleep 5
kubectl get pods --selector app=ubuntu
