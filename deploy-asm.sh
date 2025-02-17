#!/bin/bash
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

if [ -z "$PROJECT" ]
then
echo "No PROJECT variable set"
exit
fi

if [ -z "$LOCATION" ]
then
echo "No LOCATION variable set"
exit
fi

if [ -z "$CLUSTERNAME" ]
then
echo "No CLUSTERNAME variable set"
exit
fi

echo "Register GKE cluster to the fleet..."
gcloud container fleet memberships register $CLUSTERNAME \
    --gke-cluster $LOCATION/$CLUSTERNAME \
    --enable-workload-identity
    
echo "Enable Managed ASM on the project..."
gcloud container fleet mesh enable

echo "Wait for ASM CRD in the GKE cluster..."
for i in {1..10}; do
  if kubectl wait --for condition=established --timeout=10s crd/controlplanerevisions.mesh.cloud.google.com 2>/dev/null; then
    break
  fi
  sleep 10
done

echo "Enable Managed ASM on the GKE cluster..."
gcloud container fleet mesh update \
    --management automatic \
    --memberships $CLUSTERNAME

echo "Wait for ASM resource in the GKE cluster..."
for i in {1..10}; do
  if kubectl wait --for condition=ProvisioningFinished --timeout=10s controlplanerevision asm-managed -n istio-system  2>/dev/null; then
    break
  fi
  sleep 10
done

gcloud container clusters get-credentials $CLUSTERNAME --project=$PROJECT --zone=$LOCATION
kubectl config set-context $CLUSTERNAME

echo "Deploying Online Boutique sample application..."
kubectl create namespace onlineboutique --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace onlineboutique istio-injection=enabled
ONLINE_BOUTIQUE_VERSION=$(curl -s https://api.github.com/repos/GoogleCloudPlatform/microservices-demo/releases | jq -r '[.[]] | .[0].tag_name')
kubectl apply -f https://github.com/GoogleCloudPlatform/microservices-demo/raw/${ONLINE_BOUTIQUE_VERSION}/release/kubernetes-manifests.yaml -n onlineboutique

./orderservice/deploy.sh
./ui-ingress/deploy.sh