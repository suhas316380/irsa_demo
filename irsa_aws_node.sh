## Source
# 1. https://docs.aws.amazon.com/en_ca/eks/latest/userguide/iam-roles-for-service-accounts-cni-walkthrough.html
# 2. https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html

# Required Variables
region=$1
clusterName=$2

[[ -z "$region" || -z "$clusterName" ]] && echo "Assign region and clusterName variables to something :/  Eg: oidc_irsa_aws-node.sh us-east-1 demo-cluster" && exit 0

# Optional - Change me to use non-defaul values
serviceAccountName="aws-node"
policyARN="arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
namespace="kube-system"

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

######################################### Optional Section END  ###############################################

# This section covers the case of a CLuster not created using eksctl and/or the OIDC Endpoint does not exist which is the case with older clusters

oidc_endpoint_check=$(aws eks describe-cluster --name ${clusterName} --query cluster.identity.oidc.issuer --output text --region $region)
if [[ "${oidc_endpoint_check}" != "https://oidc.eks."* ]]; then

  # Get ThumbPrint
  OpenIDEndpoint="https://oidc.eks.${region}.amazonaws.com/id/$(aws eks describe-cluster --name ${clusterName} --region $region | jq -r '.cluster | .endpoint' | cut -d. -f1 | cut -c9-)"
  ServerName=$(curl -s "${OpenIDEndpoint}/.well-known/openid-configuration" | jq -r '.jwks_uri' | sed 's/\.com.*/.com/' | cut -c9-)

  # openssl s_client -servername $ServerName -showcerts -connect ${ServerName}:443 2>/dev/null </dev/null |  sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'

  # Get Certificate and store them as .pem ; We need only Root CA that starts with "Starfield_Services_Root_Certificate_Authority"
  openssl s_client -servername $ServerName -showcerts -connect ${ServerName}:443 < /dev/null | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; out="cert"a".crt"; print >out}' && for cert in *.crt; do newname=$(openssl x509 -noout -subject -in $cert | sed -n 's/^.*CN=\(.*\)$/\1/; s/[ ,.*]/_/g; s/__/_/g; s/^_//g;p').pem; mv $cert $newname; done
  mkdir -p certs && mv *.pem certs/

  # Generate Fingerprint of the cert
  numberOfCerts=$(ls certs/ | wc -l)
  [[ $numberOfCerts -eq 0 ]] && echo "something went wrong. Manually Run: openssl s_client -servername ${ServerName} -showcerts -connect ${ServerName}:443 2>/dev/null </dev/null |  sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' to see what's going on" && exit 1

  [[ $numberOfCerts -eq 1 ]] && certName='certs/*.pem' || certName='certs/Starfield_Services_Root_Certificate_Authority*.pem'
  ROOT_CA_FINGERPRINT=$(openssl x509 -in $certName -fingerprint -noout | awk -F '=' '{print $2}' |tr -d ":" |tr -d "\n")

  # Create Connect Provider
  aws iam create-open-id-connect-provider --url $OpenIDEndpoint --thumbprint-list $ROOT_CA_FINGERPRINT --client-id-list sts.amazonaws.com --region $region

fi
######################################### Optional Section END  ###############################################

# Create Service account
eksctl create iamserviceaccount --name $serviceAccountName --namespace $namespace --cluster $clusterName --attach-policy-arn $policyARN --approve --override-existing-serviceaccounts

RoleARN=$(kubectl get sa $serviceAccountName -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role\-arn}')

echo $RoleARN

# Optional - Update the CNI version
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.5/config/v1.5/aws-k8s-cni.yaml

# Test if everything is working - Get aws-node pod logs
for i in $(kubectl get pods -n kube-system -o wide -l k8s-app=aws-node | egrep "aws-node" | grep Running | awk '{print $1}'); do echo $i ; kubectl logs $i -n kube-system; echo; done
