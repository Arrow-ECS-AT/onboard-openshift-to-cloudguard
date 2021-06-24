#!/bin/bash

# A script to onboard OpenShift cluster to CloudGuard
# Author: Jayden Kyaw Htet Aung (Regional Cloud & DevSecOps Architect, Check Point)
# Extended by: Thomas Marko <thomas.marko@arrow.com> (Arrow ECS Austria, Solution Designer)

usage() {
	echo "USAGE: $0 -k <api-key> -s <api-secret> -p <projectname> -n <clustername> -r <api-region>"
}

exit_abnormal() {
	usage
	exit 1
}

get_dome9_agent_api_url() {
	case "$1" in
		"eu1")
			echo "https://api-cpx.eu1.dome9.com/v2"
			;;
		*)
			echo "https://api-cpx.dome9.com/v2"
			;;
	esac
}

get_dome9_onboarding_api_url() {
	case "$1" in
		"eu1")
			echo "https://api.eu1.dome9.com/v2"
			;;
		*)
			echo "https://api.dome9.com/v2"
			;;
	esac
}

if [[ $# -lt 1 ]]; then exit_abnormal; fi 

while getopts ":k:s:p:n:r:h" options;
do
	case ${options} in
		k)
			CHKP_CLOUDGUARD_API=${OPTARG}
			;;
		s)
			CHKP_CLOUDGUARD_SECRET=${OPTARG}
			;;
		p)
			namespace=${OPTARG}
			oc get project $namespace >/dev/null 2>&1
 			if [[ $? -eq 0 ]]
			then
				read -p "Project $namespace already exists on your cluster. Do you want to continue (y/n)? " -n 1 -r
				if [[ ! $REPLY =~ ^[Yy]$ ]]
				then
    					[[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
				fi
			else
				echo -n "Creating project $namespace... "
				oc new-project $namespace >/dev/null 2>&1
				echo "Done."
			fi
			;;
		n)
			cluster_name=${OPTARG}
			if jq -ne . >/dev/null 2>&1 <<<"$response"
			then
        			echo $response
    				[[ "$0" = "$BASH_SOURCE" ]] && exit 2 || return 2 # handle exits from shell or function but don't exit interactive shell
			fi
			;;

		r)
			region=${OPTARG}
			;;
		:)
			echo "Error: -${OPTARG} requires an  argument."
			exit_abnormal
			;;
		*)
			exit_abnormal
			;;
	esac
done

dome9OnboardingApiUrl=$(get_dome9_onboarding_api_url $region)
dome9AgentApiUrl=$(get_dome9_agent_api_url $region)

echo -n "Onboarding cluster in CloudGuard... "
cluster_id=$(curl -s  -X POST $dome9OnboardingApiUrl/KubernetesAccount -H "Content-Type: application/json" -H "Accept: application/json" -d "{\"name\": \"$cluster_name\"}" --user $CHKP_CLOUDGUARD_API:$CHKP_CLOUDGUARD_SECRET | jq -r '.id')
echo "Done (Cluster-ID: $cluster_id)."
	
# Generate secret
oc get secret dome9-creds -n $namespace > /dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo -n "Creating secret for API authentication... "
	oc create secret generic dome9-creds \
		--from-literal=username=$CHKP_CLOUDGUARD_API \
		--from-literal=secret=$CHKP_CLOUDGUARD_SECRET \
		--namespace $namespace >/dev/null 2>&1
	echo "Done."
else
	echo "Secret already exists."
fi

# Create Configmap
oc get configmap cp-resource-management-configmap --namespace $namespace >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo -n "Creating config map (ClusterID: $cluster_id, API-URL: $dome9AgentApiUrl)... "
	oc create configmap cp-resource-management-configmap \
		--from-literal=cluster.id=$cluster_id \
		--from-literal=dome9url=$dome9AgentApiUrl \
		--namespace $namespace >/dev/null 2>&1
	echo "Done."
else
	echo "Config Map already exists."
fi

# Create Services account
oc get serviceaccount cp-resource-management --namespace $namespace >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo -n "Creating service account... "
	oc create serviceaccount cp-resource-management --namespace $namespace >/dev/null 2>&1
	echo "Done."
else
	echo "Service account already exists."
fi

# Create Admin User. Make sure uid1000.json is in the same directory.
if [[ ! -e ${PWD}/uid1000.json ]]
then
	echo "Fatal: Missing file uid1000.json! Aborting!"
	exit 4
else
	echo "INFO: Found file ${PWD}/uid1000.json. "
fi

# Create Security Context Constraint to allow the agent to run as uid 1000
oc get securitycontextconstraints.security.openshift.io uid1000 >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo -n "Creating Security Context Constraint to allow running as UID 1000... "
	oc create -f uid1000.json --as system:admin >/dev/null 2>&1
	echo "Done."
else
	echo "Security Context Constraint already exists."
fi

# Add policy to service account
echo -n "Adding SCC to user... "
oc adm policy add-scc-to-user uid1000 -z cp-resource-management --as system:admin >/dev/null 2>&1
echo "Done."

# Create Cluster role
oc get clusterrole cp-resource-management >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo "Creating clusterrole... "
	oc create clusterrole cp-resource-management \
		--verb=get,list \
		--resource=pods,nodes,services,nodes/proxy,networkpolicies.networking.k8s.io,ingresses.extensions,podsecuritypolicies,roles,rolebindings,clusterroles,clusterrolebindings,serviceaccounts,namespaces >/dev/null 2>&1
	echo "Done."
else
	echo "Clusterrole already exists."
fi

# Clusterrole binding
oc get clusterrolebinding cp-resource-management >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo "Creating cluster role binding... "
	oc create clusterrolebinding cp-resource-management \
		--clusterrole=cp-resource-management \
		--serviceaccount=$namespace:cp-resource-management >/dev/null 2>&1
	echo "Done."
else
	echo "Cluster role binding already exists."
fi

# Deploy CloudGuard 
if [[ ! -e ${PWD}/cp-cloudguard-openshift.yaml ]]
then
	echo "Fatal: Missing template file cp-cloudguard-openshift.yaml.tmpl! Aborting!"
	exit 4
else
	echo "INFO: Found file ${PWD}/cp-cloudguard-openshift.yaml. "
fi

oc get deployment cp-resource-management --namespace $namespace >/dev/null 2>&1
if [[ $? -ne 0 ]]
then
	echo "Creating deployment for agent... "
	oc create -f cp-cloudguard-openshift.yaml --namespace=$namespace >/dev/null 2>&1
	echo "Done."
else
	echo "Deployment already exists."
fi

echo Cluster onboarding has finished successfully.
