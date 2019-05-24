#!/bin/bash
set -e
set -x

if [ -z $CI_SFDX_USERNAME ];then
  echo "You must define CI_SFDX_USERNAME with your HubOrg username"
  exit 1
fi

if [ ! -f "$CI_PROJECT_DIR/$CI_SFDX_KEY" ];then
  echo "$CI_PROJECT_DIR/$CI_SFDX_KEY must be present"
  exit 1
fi

if [ ! -f "$CI_PROJECT_DIR/$CI_SFDX_SCRATCH_DEF" ];then
  echo "$CI_PROJECT_DIR/$CI_SFDX_SCRATCH_DEF must be present"
  exit 1
fi

# Authenticate
sfdx force:auth:jwt:grant --clientid $CI_SFDX_CONSUMER_KEY --jwtkeyfile "$CI_PROJECT_DIR/$CI_SFDX_KEY" --username $CI_SFDX_USERNAME --setdefaultdevhubusername -a GitlabCICDExt

# Create package version
PACKAGEVERSION="$(sfdx force:package:version:create --package $PACKAGENAME --installationkeybypass --wait 10 --json --targetdevhubusername GitlabCICDExt | jq '.result.SubscriberPackageVersionId' | tr -d '"')"
sleep 300 # Wait for package replication.
echo ${PACKAGEVERSION}

# Create scratch org
sfdx force:org:create --targetdevhubusername GitlabCICDExt --setdefaultusername --definitionfile "$CI_PROJECT_DIR/$CI_SFDX_SCRATCH_DEF" --setalias installorg --wait 10 --durationdays 1
sfdx force:org:display --targetusername installorg

# Install package in scratch org
sfdx force:package:install --package $PACKAGEVERSION --wait 10 --targetusername installorg

# Run unit tests in scratch org and deliver back json coverage and junit results for gitlab merge request info
sfdx force:apex:test:run --targetusername installorg --wait 10 --testlevel $TESTLEVEL --wait 10 -c -r json | tee result.json
cat result.json | python -c "import json, sys; c=reduce(lambda x, y : (x[0]+y[0], x[1]+y[1]),[(x['totalCovered'], x['totalLines']) for x in json.load(sys.stdin)['result']['coverage']['coverage']], (0, 0)); print 'Total Coverage: %f' % (c[0]/float(c[1])*100 if c[1] else 100)"
TEST_RUN_ID=$(cat result.json | python -c "import json, sys; data = json.load(sys.stdin); print(data['result']['summary']['testRunId']);")
OUTCOME=$(cat result.json | python -c "import json, sys; data = json.load(sys.stdin); print(data['result']['summary']['outcome']);")
#CURRENTHOST=$(cat result.json | python -c "import json, sys; data = json.load(sys.stdin); print(data['result']['summary']['outcome']);")
echo "$TEST_RUN_ID is our test ID to return result.xml"
mkdir -p testout
sfdx force:apex:test:report -i $TEST_RUN_ID -r junit -d testout/
#export $CURRENTHOST
sfdx force:org:delete --targetusername installorg --noprompt

#if [ ! $OUTCOME = "Passed" ]; then
#    # Delete scratch org since the pipeline is failed
#    sfdx force:org:delete --targetusername installorg --noprompt
#    echo "Deleted our scratch org as our tests and pipeline have failed"
#    exit 1
#fi


