# Avium Labs Apache Tomcat Docker Image

This is an Apache Tomcat 9 OpenJDK 21 Docker image based on Alpine Linux 
docker image.

This image uses the Apache Tomcat instances architecture in an attempt to 
insulate deployed webapps from Tomcat version upgrades.

There are 5 volumes to plug-in;
- backup  
- instance conf  
- instance logs  
- instance webapps  
- secrets  

The logging properties are modified to identify the log files from a specific 
instance. The instance naming convention does guarantee uniqueness.

The initial configuration settings are in the tomcat.config file.
Modify these settings per your environments requirements.

A self-signed certificate is generated and a connector is defined for port 8443.

The manager webapp is activated and the default passwords are located in the 
/opt/secrets volume.


### TLS Certificate
A TLS certificiate is generated at build time. The certificate information is 
generated based on the values defined in the tomcat.config file's `keystore` 
section.


## Build an Image

### Build Default

**Regular build**
```shell
export TC_VERSION=9.0.121
```

```shell
docker build --pull --no-cache -t aviumlabs/tomcat:$TC_VERSION-alpine .
```

**Build with sbom and provenance** 
```shell
docker build --pull --no-cache -t aviumlabs/tomcat:$TC_VERSION-alpine --provenance=mode=max --sbom=true .
```

```shell
export INST_NAME=tc1
```

```shell
docker run -h ap1.aviumlabs.test --name ap1 -p 8080:8080 -p 8443:8443 -v ap1_tc_backup:/opt/backup -v ap1_tc_inst_logs:/opt/tomcat/instances/$INST_NAME/logs -v ap1_tc_inst_conf:/opt/tomcat/instances/$INST_NAME/conf -v ap1_tc_secrets:/opt/secrets -v ap1_tc_inst_webapps:/opt/tomcat/instances/$INST_NAME/webapps -it --rm aviumlabs/tomcat:$TC_VERSION-alpine
```

Push to docker hub:
```shell 
docker push aviumlabs/tomcat:$TC_VERSION-alpine
```


## Runtime

```shell
docker exec -it ap1 /bin/ash
```

## Tomcat Testing

Test the pre-configured rpa user.
- The configured rpa account is: `rpatomcat`
- The generated password for the account is in the `/opt/secrets/rpauser.pass` file.

```shell
curl -k -u <username:password> https://localhost:8443/manager/text/list
```

>  
> OK - Listed applications for virtual host [ap1.aviumlabs.test]  
> /manager:running:0:/usr/local/tomcat/webapps/manager  
>  



## Issues

### commons-daemon compile

Not currently utilizing jsvc to manage instances.

```
In file included from jsvc-unix.c:17:
jsvc.h:32:5: error: cannot use keyword 'false' as enumeration constant
32 |     false,
|     ^~~~~
jsvc.h:32:5: note: 'false' is a keyword with '-std=c23' onwards
jsvc.h:34:3: error: expected ';', identifier or '(' before 'bool'
34 | } bool;
```

https://www.mail-archive.com/pkg-java-maintainers@alioth-lists.debian.net/msg33392.html

https://github.com/apache/commons-daemon