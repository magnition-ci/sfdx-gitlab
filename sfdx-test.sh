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

sfdx force:auth:jwt:grant --clientid $CI_SFDX_CONSUMER_KEY --jwtkeyfile "$CI_PROJECT_DIR/$CI_SFDX_KEY" --username $CI_SFDX_USERNAME --setdefaultdevhubusername -a GitlabCICDExt
sfdx force:org:create -v GitlabCICDExt -s -f "$CI_PROJECT_DIR/$CI_SFDX_SCRATCH_DEF" -a $CI_SFDX_ORG
sfdx force:source:push -u $CI_SFDX_ORG
sfdx force:apex:test:run -u $CI_SFDX_ORG --wait 10 -c -r json | tee result.json
cat result.json | python -c "import json, sys; c=reduce(lambda x, y : (x[0]+y[0], x[1]+y[1]),[(x['totalCovered'], x['totalLines']) for x in json.load(sys.stdin)['result']['coverage']['coverage']], (0, 0)); print 'Total Coverage: %f' % (c[0]/float(c[1])*100 if c[1] else 100)"
TEST_RUN_ID=$(cat result.json | python -c "import json, sys; data = json.load(sys.stdin); for testrunid in data['result']['summary']['testRunId'] : print(testrunid)")
echo "$TEST_RUN_ID is our test ID to return result.xml"
sfdx force:apex:test:report -i $TEST_RUN_ID -r junit | tee report.xml
cat report.xml
sfdx force:org:delete -u $CI_SFDX_ORG -p
echo "Completed our SFDX testing stage"
