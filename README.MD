# IBM API Connect Essentials OCP Installation overview

<p>
 This is short overview how to install API Connect Essentials on TechZone cluster or any other cluster regarding existing AWS type of deployments.
</p>
<h3> Requirements </h3>

- OCP 4.12 and user account with administrator privileges
- IBM entitlement key for accessing [IBM Container Software Library](https://myibm.ibm.com/products-services/containerlibrary)
- PostgreSQL DB (version 15+)

## Agenda

- [IBM API Connect Essentials OCP Installation overview](#ibm-api-connect-essentials-ocp-installation-overview)
  - [Agenda](#agenda)
  - [Step-by-step prerequisites](#step-by-step-prerequisites)
    - [(Optional) PostgreSQL installation](#optional-postgresql-installation)
  - [Operator installation](#operator-installation)
  - [Set up routes](#set-up-routes)
  - [Verify the instalation](#verify-the-instalation)
  - [Install Introspection Service(Optional)](#install-introspection-serviceoptional)
  - [Add user accounts](#add-user-accounts)
  - [Getting started with APIC Essential](#getting-started-with-apic-essential)
    - [Make first graphql api](#make-first-graphql-api)
  - [TBD](#tbd)


## Step-by-step prerequisites 
* <p> Get entitlement key,
        navigate to IBM Container library and create/copy your entitlement key
![entitlement](./images/entitlement.png)
* <p> Create namespace

```shell
oc new project apic
oc project apic
```

* <p> Create secrets 

docker-registry secret will be used to authentificate and pull apic operator
db-secret will be used to connect to Postgresql instance, where <dsn> is a string of the form postgresql://user:password@host/database.

```shell
oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=<IBM entitlement key>
oc create secret generic db-secret --from-literal=DSN=<dsn>
```

* <p> Check secrets 

![ibm-entitlement-key secret](./images/ibm-entitlement-key.png)
![db-secret](./images/db-secret.png)



### (Optional) PostgreSQL installation

In this setup CrunchyPostgres Operator is installed[https://github.com/CrunchyData/postgres-operator] - "*Production Postgres Made Easy*"

You can use whatever Postgresql instance you wish. This was the fastest way for me to setup Postgresql instance up and running.

The **PostgresCluster** CRD is created with default specification. 
For production environment you will need to setup PostgeSQL to fit your needs.
![crunchy-postgres](./images/crunchy-postgres.png)

Under secrets you can find secret named "**apic-postgres-pguser-apic-postgres**" created by operator
and copy/reveal dbname,host,password,port,uri,user and verifier entries.

To get dsn literal check **uri** entry under *apic-postgres-pguser-apic-postgres* secret.

## Operator installation

<p> Download and extract the *CASE BUNDLE*

1. Navigate to https://github.com/IBM/cloud-pak/tree/master/repo/case/ibm-stepzen-case and pick the latest bundle
![case-bundle](./images/CASE%20bundle.png)

2. Download bundle and extract 
![case-b](./images/case-bundle-version.png)

    <code> tar zxvf ibm-stepzen-case-<version+timestamp>.tgz </code>

3. Navigate to *ibm-stepzen-case/inventory/stepzenGraphOperator/files/deploy*

 - **crd.yaml** is CRD used to configure operator 
 - **operator.yaml** defines operator resources, service account and associated roles


4. Apply files
    ```shell
    oc apply -f crd.yaml
    oc apply -f operator.yaml
    ```
5.  Create CR that defines configuration setting for StepZen server deployment

    **Minimum requirements**:
    * Accept the license agreement
        * Review License agreement and set spec.licence.accept: True
    * Add ibm-entitlement-key-secret
        * Set .imagePullSecret to ibm-entitlement-key
    * Add Postgresql secret
        * Set .controlDatabaseSecret to db-secret

    You can specify horizontal pod autoscaling parameters such as min and max Replicas, *targetCPUUtilization*, add custom *labels/annotations* to pods etc.

     [View full spec option list](https://www.ibm.com/docs/en/api-connect/ace/1.x?topic=essentials-cr-configuration-settings)

    You can also check example **cr.yaml** file in this repository.


6. Apply custom configuration
```shell 
    oc apply -f cr.yaml
```
7. Verify that operator is running : 
```shell
    oc get StepZenGraphServer
```
```shell
expected output:    
    NAME STATUS SUMMARY             AGE
    apic Ready Services are ready    /
```




<p>
There are two services configuration sections: <strong> graphServer </strong> and <strong> graphServerSubscription </strong>.
You can set parameters like  <em> scaling options, pod annotations, and node affinities </em> for each of the two services.

The <em> graphServer section </em> is <strong> required </strong> and the <em> graphServerSubscription </em> section is <strong>optional </strong>

You must define the limits and horizontal scaling parameters for the two services separately. The optimal values will depend on the capacity of your nodes, how many requests of each sort (query/subscription) you expect per unit of time, and how responsive your application needs to be.

![services](./images/services.png)


> **_NOTE:_** default *stepzen*  namespace is changed to *apic* 
```yaml
metadata.namespace: apic
```

## Set up routes

**Prerequisites**:

 - Operator installation completed successfully
 - Cluster address available(*i.e. 662945b10b45af001eacf950.cloud.techzone.ibm.com*)
 - You installed [cert-manager] (https://github.com/cert-manager/cert-manager)
 -  The [letsencrypt](https://letsencrypt.org/) or any other CA for your deployment


1. Install OpenShift cert-manager Route Support: [openshift-routes](https://github.com/cert-manager/openshift-routes)
```shell 
oc apply -f https://github.com/cert-manager/openshift-routes/releases/latest/download/cert-manager-openshift-routes.yaml
```

2. Create file [stepzen-route.yaml](./routes/stepzen-route.yaml)

3. Create [grapql-routes.yaml](./routes/graphql-routes.yaml) - routes for graphql account

4. Apply both files

> [!IMPORTANT] 
> For each account that you want to add to your deployment, you must add a new pair of routes mapping account.graphserver.cluster and account.graphserver.apps.cluster/stepzen-subscriptions to the stepzen-graph-server.

## Verify the instalation
Open a browser and navigate to https://stepzen.domain/version
![verify](./images/verify.png)

## Install Introspection Service(Optional)

TBD

## Add user accounts

**stepzen-admin.sh**  on path: *ibm-stepzen-case/inventory/stepzenGraphOperator/files/deploy* is script designed for diverse administrative functions

You can create accounts, retrieval API keys, remove accounts, generate keys.

- Add-account:
```shell
./stepzen-admin.sh add-account graphql
```
If acc already exists it will just retrieve keys.
In this case since graphql is existing acc - it will just retrieve keys.

- Create new acc:
```shell
./stepzen-admin.sh add-account demouser
```
    
> **_NOTE:_** stepzen-admin.sh is changed because renamed stepzen namespace(called apic).

For additional script usage look at [official docs](https://www.ibm.com/docs/en/api-connect/ace/1.x?topic=essentials-exploring-admin-script#admin_script__Command)

> [!IMPORTANT]  API Connect Essentials expects each user account's endpoint URL to start with the account name. If you did not set up a wildcard route/ingress for <*.my-domain> during installation, then for each account that you add to your deployment, you must add a new pair of route/ingress mappings account.graphserver.apps.cluster/ and account.graphserver.apps.cluster/stepzen-subscriptions to the stepzen-graph-server service and the stepzen-graph-server-subscription service, respectively.s


## Getting started with APIC Essential 

* Install stepzen cli
```shell
 npm install -g stepzen
```
* (Optional) Install [graphql-playground](https://github.com/graphql/graphql-playground)


### Make first graphql api 

Run following commands:

```shell
stepzen init --endpoint=api/product-demo
stepzen import curl "https://introspection.apis.stepzen.com/customers" --query-name "customers"
stepzen start
```

Now you are all setup to start use this fabulous graphql management tool :) 

StepZen server starts at port 5001:
<p>


> Deploying api/product-demo to StepZen... done in 253ms 🚀
  ✓ 🔐 https://graphql.apps.662945b10b45af001eacf950.cloud.techzone.ibm.com/api/product-demo/__graphql
  ✓ 🔐 wss://graphql.apps.662945b10b45af001eacf950.cloud.techzone.ibm.com/stepzen-subscriptions/api/product-demo/__graphql (subscriptions)

You can test your hosted converted API with curl:

```shell
curl https://graphql.apps.662945b10b45af001eacf950.cloud.techzone.ibm.com/api/product-demo/__graphql \
   --header "Authorization: Apikey $(stepzen whoami --apikey)" \
   --header "Content-Type: application/json" \
   --data-raw '{
     "query": "query SampleQuery { __schema { description queryType { fields {name} } } }"
   }'

```
If you go to http://localhost:5001/api/product-demo you can start using this base customer orders demo.

You can query graphql from ![playground IDE](./images/grphql-playground.png)



> **_NOTE:_** In this tutorial the focus is on installation - for more examples look at [official snippets)(https://github.com/stepzen-dev/snippets) or  great [JSON samples repo](https://github.com/learnwithjason/lets-learn-stepzen)].

