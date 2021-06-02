# Automate Onboarding an Openshift cluster to Check Point CloudGuard Native

This script will automatically onboard a Red Hat OpenShift Cluster (tested with Version 4.7) to Check Point CloudGuard Native.

It is heavily based on the work of Jayden Aung (https://github.com/jaydenaung/cloudguard-onboard-openshift) and Dean Houari (https://github.com/chkp-dhouari/cloudguard-OpenShift) and adds some improvements like a bit better error handling and also the ability to use different API regions. It also fixes some issues with the original code.

## Prerequisites

You have to have or create an Check Point Infinity or Dome9 account in order to continue. If you don't have one, you can create on for free at https://portal.checkpoint.com/create-account.

In Infinity Portal you have to create a service account by visiting the Cloudguard Settings page. The service account needs a role that has onboarding permissions.

## Onboarding

The script supports the -h option which display a usage help:

```USAGE: ./onboard.sh -k <api-key> -s <api-secret> -p <projectname> -n <clustername> -r <api-region>```

## Bug Reporting

If you find a bug please create a Github issue.

## Disclaimer

This script is provided as is and we do not provide any support. If you have questions regarding the onboarding process, please contact Check Point support. If you find a bug or a security issue, please file a Github issue.