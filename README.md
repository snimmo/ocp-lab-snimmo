# ocp-lab-snimmo

Cleanup
```
oc delete pods --all-namespaces --field-selector=status.phase=Succeeded
oc delete pods --all-namespaces --field-selector=status.phase=Failed
```

## Install OpenShift GitOps

After logging into your OpenShift Cluster using the oc cli, run the following script.
```
./install-openshift-gitops.sh
```

```
oc apply -f cluster/cluster-application.yaml
```