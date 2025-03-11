#!/bin/bash

# Exit on any error
set -e

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Verify if 'oc' CLI is installed
if ! command_exists oc; then
  echo "Error: 'oc' CLI is not installed. Please install it and log in to your OpenShift cluster."
  exit 1
fi

# Check if logged in to OpenShift cluster
if ! oc whoami > /dev/null 2>&1; then
  echo "Error: You are not logged in to an OpenShift cluster. Please log in using 'oc login'."
  exit 1
fi

# Create the OpenShift GitOps namespace
NAMESPACE="openshift-gitops-operator"
echo "Creating namespace: $NAMESPACE"
oc create namespace $NAMESPACE > /dev/null 2>&1 || echo "Namespace $NAMESPACE already exists."

# Create the OpenShift GitOps OperatorGroup
echo "Creating OpenShift GitOps OperatorGroup"
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: $NAMESPACE
spec:
  upgradeStrategy: Default
EOF

# Install the OpenShift GitOps Operator
echo "Installing OpenShift GitOps Operator"
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: $NAMESPACE
spec:
  channel: latest 
  installPlanApproval: Automatic
  name: openshift-gitops-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace 
EOF


# Wait for the CSV to be created
echo "Checking that the ClusterServiceVersion for OpenShift GitOps Operator is created..."
while ! oc get csv -n $NAMESPACE -l operators.coreos.com/openshift-gitops-operator.$NAMESPACE > /dev/null 2>&1; do
  echo "Waiting for CSV for OpenShift GitOps Operator to be created..."
  sleep 5
done
echo "ClusterServiceVersion for OpenShift GitOps Operator is created..."

echo "Waiting for the operator to install..."
# We wait until the CSV status shows 'Succeeded'
TIMEOUT=300
END=$((SECONDS + TIMEOUT))

while true; do
  CSV_STATUS=$(oc get csv -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.displayName=="Red Hat OpenShift GitOps")].status.phase}')
  if [ "$CSV_STATUS" = "Succeeded" ]; then
    echo "OpenShift GitOps operator installed successfully!"
    break
  fi

  if [ $SECONDS -gt $END ]; then
    echo "ERROR: Timed out waiting for the OpenShift GitOps operator to install."
    exit 1
  fi
  
  sleep 10
done


# Verify the installation
echo "Verifying OpenShift GitOps installation..."
oc get all -n $NAMESPACE

# Add ClusterRoleBinding for the default service account
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-app-controller-cluster-binding
subjects:
  - kind: ServiceAccount
    name: openshift-gitops-argocd-application-controller
    namespace: openshift-gitops
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# Output the Argo CD server route
echo "Fetching the Argo CD server route..."
ARGOCD_ROUTE=$(oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}')

if [ -n "$ARGOCD_ROUTE" ]; then
  echo "OpenShift GitOps (Argo CD) installation completed successfully."
  echo "Access the Argo CD Web UI at: https://$ARGOCD_ROUTE"
else
  echo "Error: Failed to retrieve the Argo CD server route."
fi