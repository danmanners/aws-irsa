#!bash

# USAGE:    ./02-gen-oidc-endpoint.sh
# OR        ./02-gen-oidc-endpoint.sh BucketName 
# OR        ./02-gen-oidc-endpoint.sh BucketName s3-region-id.path.amazonaws.com

PRIV_KEY="keys/oidc-issuer.key"
PUB_KEY="keys/oidc-issuer.key.pub"
PKCS_KEY="keys/oidc-issuer.pub"

# Only if --replaceKeys is an argument:
if [ "--replaceKeys" in $@ ]; then
    # Clear out any existing keys, create new ones, and convert
    # the SSH pubkey to PKCS8 Format
    rm -rf keys && mkdir -p keys
    ssh-keygen -t rsa -b 4096 -f $PRIV_KEY -m pem -N ""
    ssh-keygen -e -m PKCS8 -f $PUB_KEY > $PKCS_KEY
fi

# Set The S3 Bucket Environment Variables
AWS_DEFAULT_REGION=${$(aws configure get region):-us-east-2}
# Check if the replaceKeys value is argument 1 or two; don't set `--replaceKeys` to the environment variable
if [ "$1" != "--replaceKeys" ]; then
    S3_BUCKET=$(lowerCaseOnly ${1:-aws-irsa-oidc-$(date +%s)})
fi

if [ "$2" != "--replaceKeys" ]; then
    S3_REGION=$(lowerCaseOnly ${2:-s3.amazonaws.com})
fi

ISSUER_HOSTPATH=$S3_BUCKET.$S3_REGION

# Create the S3 Bucket; make sure it's all lowercase
aws s3api create-bucket \
    --bucket $S3_BUCKET \
    --create-bucket-configuration \
    LocationConstraint=$AWS_DEFAULT_REGION

# Create discover.json and keys.json
cat <<EOF > discovery.json
{
    "issuer": "https://$ISSUER_HOSTPATH/",
    "jwks_uri": "https://$ISSUER_HOSTPATH/keys.json",
    "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
    "response_types_supported": [
        "id_token"
    ],
    "subject_types_supported": [
        "public"
    ],
    "id_token_signing_alg_values_supported": [
        "RS256"
    ],
    "claims_supported": [
        "sub",
        "iss"
    ]
}
EOF

# Generate the Keys JSON file
go run ./main.go -key $PKCS_KEY | \
jq '.keys += [.keys[0]] | .keys[1].kid = ""' > keys.json

# Upload the 'discovery.json' and 'keys.json' files to AWS S3
aws s3 cp --acl public-read \
    ./discovery.json \
    s3://$S3_BUCKET/.well-known/openid-configuration

aws s3 cp --acl public-read \
    ./keys.json \
    s3://$S3_BUCKET/keys.json

# Create OIDC identity provider
CA_THUMBPRINT=$(openssl s_client \
    -connect $S3_REGION:443 \
    -servername s3.amazonaws.com \
    -showcerts < /dev/null 2>/dev/null | \
    openssl x509 -in /dev/stdin -sha1 \
    -noout -fingerprint | \
    cut -d '=' -f 2 | tr -d ':'
)

# Create the OIDC Provider in AWS
aws iam create-open-id-connect-provider \
    --url https://$ISSUER_HOSTPATH \
    --thumbprint-list $CA_THUMBPRINT \
    --client-id-list sts.amazonaws.com | jq

if [ "$?" -ne "0" ]; then
    echo "The service-account-issuer as below:"
    echo "https://$ISSUER_HOSTPATH"
else
    echo "The service-account-issuer as below:"
    echo "https://$ISSUER_HOSTPATH"
fi
