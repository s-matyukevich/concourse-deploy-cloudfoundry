#!/bin/bash -e

fly -t $FOUNDATION_NAME login  -n  $FOUNDATION_NAME -c $CONCOURSE_URL -u $CONCOURSE_USER -p $CONCOURSE_PASSWORD

function update_pipeline()
{
  product_name=$1
  pipeline_repo=$2
  echo "Updating pipeline $product_name"
  fly -t $FOUNDATION_NAME set-pipeline -n -p deploy-$product_name \
              --config="concourse-deploy-$product_name/ci/pipeline.yml" \
              --var="vault-address=$VAULT_ADDR" \
              --var="vault-token=$VAULT_TOKEN" \
              --var="foundation-name=$FOUNDATION_NAME" \
              --var="deployment-name=$product_name" \
              --var="pipeline-repo=$pipeline_repo" \
              --var="pipeline-repo-branch=master" \
              --var="pipeline-repo-private-key=$GIT_PRIVATE_KEY" \
              --var="product-name=$product_name"
}

update_pipeline redis $DEPLOY_REDIS_GIT_URL
update_pipeline turbulence $DEPLOY_TURBULENCE_GIT_URL
update_pipeline chaos-loris $DEPLOY_CHAOS_LORIS_GIT_URL
update_pipeline bluemedora $DEPLOY_BLUEMEDORA_GIT_URL
update_pipeline firehose-to-loginsight $DEPLOY_FIREHOSE_TO_LOGINSIGHT_GIT_URL
update_pipeline spring-services $DEPLOY_SPRING_SERVICES_GIT_URL

bosh_client_id=$(vault read -field=bosh-client-id secret/bosh-$FOUNDATION_NAME-props)
bosh_client_secret=$(vault read -field=bosh-client-secret secret/bosh-$FOUNDATION_NAME-props)
bosh_cacert=$(vault read -field=bosh-cacert secret/bosh-$FOUNDATION_NAME-props)

export CONCOURSE_URI=$CONCOURSE_URL
export CONCOURSE_TARGET=$FOUNDATION_NAME
export PIPELINE_REPO_BRANCH=master
echo $GIT_PRIVATE_KEY > git-private-key.pem
export PIPELINE_REPO_PRIVATE_KEY_PATH=../git-private-key.pem
export BOSH_ENVIRONMENT=${BOSH_URL#https://}
export BOSH_CLIENT=$bosh_client_id
export BOSH_CLIENT_SECRET=$bosh_client_secret
echo $bosh_cacert > bosh-ca-cert.pem
export BOSH_CA_CERT=../bosh-ca-cert.pem

pushd concourse-deploy-rabbitmq
export PRODUCT_NAME=rabbitmq
export PIPELINE_REPO=$DEPLOY_RABBITMQ_GIT_URL
./setup-pipeline.sh
popd


all_ips=$(prips $(echo "$PCF_SERVICES_STATIC" | sed 's/-/ /'))
OLD_IFS=$IFS
IFS=$'\n'
all_ips=($all_ips)
IFS=$OLD_IFS

echo "0" > index
get_ips(){
  index=$(cat index)
  res=""
  new_index=$(($index + $1))
  for ((i = $index; i < $new_index; i++))
  do
    res="$res,${all_ips[$i]}"
  done
  echo "$new_index" > index
  echo "$res" | cut -c 2-
}


pushd concourse-deploy-p-mysql
export PRODUCT_NAME=p-mysql
export PIPELINE_REPO=$DEPLOY_P_MYSQL_GIT_URL
cat > deployment-props.json <<EOF
{
  "network": "network-name",
  "ip": "$(get_ips 4)", 
  "proxy-ip": "$(get_ips 4)", 
  "monitoring-ip": "$(get_ips 4)", 
  "broker-ip": "$(get_ips 4)", 
  "base-domain": "$SYSTEM_DOMAIN",
  "notification-recipient-email": "noreply@vmware.com",
  "az": "az1",
  "pivnet_api_token": "$PIVNET_API_TOKEN",
  "syslog-address": "" 
}
EOF

./setup-pipeline.sh
popd
