bkoptag=0.1.2-42-659f239
bkversion=0.9.0-2641.0c98b91cd
prvgoptag=0.5.2-211-24bb31d0
prvgversion=0.9.0-2725.77b13981a
BUCKET_NAME=ecs4pravega_bkt_`date +%s`
PREFIX=example_`date +%s`
objStoreName=shanghai-flex

cd /root/pravega-operator
MG_EXT_IP=`kubectl get svc -l operator=objectscale-operator,component=management-gateway|grep management-gateway| awk '{print $3}'`; echo MG_EXT_IP:$MG_EXT_IP
S3_IP=`kubectl get svc -l operator=objectscale-operator,component=s3| grep s3| awk '{print $3}'`; echo S3_IP:$S3_IP
export managementKey=`kubectl get secret ${objStoreName}-initial-user -o yaml|grep managementKey:|grep -v "{}" | awk '{print $2}'|sed 's/\\n//g' |base64 --decode`; echo managementKey:$managementKey
export accessKey=`kubectl get secret ${objStoreName}-initial-user -o yaml|grep accessKey:|grep -v "{}" | awk '{print $2}'|sed 's/\\n//g' |base64 --decode`; echo accessKey:$accessKey
export secretKey=`kubectl get secret ${objStoreName}-initial-user -o yaml|grep secretKey:|grep -v "{}" | awk '{print $2}'|sed 's/\\n//g' |base64 --decode`; echo secretKey:$secretKey
export TOKEN=`curl -s -k -u root:$managementKey https://${MG_EXT_IP}:4443/login -D - -o /dev/null | grep X-SDS-AUTH-TOKEN | tr -cd '\40-\176'`; echo $TOKEN
curl  -k -H "$TOKEN" -H 'Accept:application/json' -H 'Content-Type:application/json' -X POST -d '{"name": "'"${BUCKET_NAME}"'" , "namespace": "'"${objStoreName}"'", "owner": "'"${accessKey}"'" }'  https://${MG_EXT_IP}:4443/object/bucket
echo "created internal bucket" 
cd /root/
kubectl delete secret pravega-ecs-tier2-secret
cat <<EOF > tier2-secret.yaml
apiVersion: v1
stringData:
  ACCESS_KEY_ID: $accessKey
  SECRET_KEY: $secretKey
kind: Secret
metadata:
  name: pravega-ecs-tier2-secret
  namespace: default
type: Opaque
EOF
# sed '/ACCESS_KEY_ID/s/$/'"$accessKey"'/'  tier2-secret-template.yaml  |sed '/SECRET_KEY/s/$/'"$secretKey"'/' > tier2-secret.yaml
kubectl create -f tier2-secret.yaml
cd /root/pravega-operator
helm install prvg  charts/pravega --set zookeeperUri=10.103.220.67:2181 --set bookkeeperUri=prvgbk-bookkeeper-bookie-headless:3181 --set version=$prvgversion \
--set pravega.longtermStorage.configUri=http://${S3_IP}:80?namespace=${objStoreName}%26smartClient=false \
--set pravega.longtermStorage.bucket=${BUCKET_NAME} \
--set pravega.longtermStorage.prefix=${PREFIX} \
--set pravega.longtermStorage.credentials=pravega-ecs-tier2-secret
until  [[ $( kubectl get -o jsonpath="{.items[0].status.conditions[?(@.type=='PodsReady')].status}" PravegaCluster| grep True) = True ]]; do
  echo "wait for Pravega ready..."
  sleep 15
done
echo "Pravega installed with Tier2 ECS"
