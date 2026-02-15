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


## Build an Image

### Build Default

**Regular build**  
```shell
docker build --pull --no-cache -t aviumlabs/tomcat:9.0.113-alpine .
```

**Build with sbom and provenance** 
```shell
docker build --pull --no-cache -t aviumlabs/tomcat:9.0.113-alpine --provenance=mode=max --sbom=true .
```

```shell
docker run -h ap1 --name ap1 -p 8080:8080 -p 8443:8443 -v ap1_tc_backup:/opt/backup -v ap1_tc_inst_logs:/opt/tomcat/instances/bin-a/logs -v ap1_tc_inst_conf:/opt/tomcat/instances/bin-a/conf -v ap1_tc_secrets:/opt/secrets -v ap1_tc_inst_webapps:/opt/tomcat/instances/bin-a/webapps -it --rm aviumlabs/tomcat:9.0.113-alpine
```

Push to docker hub:
```shell 
docker push aviumlabs/tomcat:9.0.113-alpine
```


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