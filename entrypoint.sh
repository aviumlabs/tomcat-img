#!/usr/bin/env python
# Copyright 2024, 2025, 2026 Michael Konrad 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import configparser
import logging
import os
import random
import re
import string
import subprocess
import sys


def main():
    tomcat_config, keystore_config = parse_config()

    #print ("Tomcat Configuration:" + str(tomcat_config))
    #print ("Keystore Configuration:" + str(keystore_config))

    if tomcat_config['configured'].lower() != 'true':
        configure_tomcat(tomcat_config, keystore_config)
        tomcat_config['configured'] = 'true'
        save_config(tomcat_config, keystore_config)

    cat_path = os.environ['CATALINA_HOME'] + r'/bin/catalina.sh'

    try:
        subprocess.run([cat_path, 'run'])
    except KeyboardInterrupt:
        print("Exiting Apache Tomcat...")

    sys.exit()


def configure_tomcat(tomcat_config: dict, keystore_config: dict):
    # Generate a random password for the keystore
    keystore_pass_path = os.environ['SECRETS_HOME'] + r'/' + keystore_config['keystore_pass']
    if not os.path.isfile(keystore_pass_path):
        keystore_pass = gen_random_password()
        with open(keystore_pass_path, 'w') as f:
            f.write(keystore_pass)

    else:
        with open(keystore_pass_path, 'r') as f:
            keystore_pass = f.read().strip()

    # Create a Java Keystore
    org = keystore_config['org']
    locality = keystore_config['locality']
    country = keystore_config['country']
    validity = keystore_config['validity']
    server_name = os.environ['HOSTNAME'] + tomcat_config['dns_domain']
    d_name = f"CN={server_name},L={locality},O={org},C={country}"
    keystore_path = os.environ['CATALINA_BASE'] + r'/conf/' + keystore_config['keystore']
    if not os.path.isfile(keystore_path):
        ks_out = subprocess.Popen(["/usr/bin/keytool",
                                   "-genkeypair",
                                   "-keyalg", "EC",
                                   "-groupname", "secp384r1",
                                   "-alias", server_name,
                                   "-dname", d_name,
                                   "-validity", validity,
                                   "-keystore", keystore_path,
                                   "-storepass", keystore_pass], 
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT)

        stdout, stderr = ks_out.communicate()

        if stderr:
            print("Error creating Java Keystore...")
            print(stderr.decode())
            sys.exit(1)
        else:
            print("Java Keystore created.")

    else:
        print("Keystore already exists, skipping creation.")

    # Configure server.xml for SSL and UTF-8 encoding
    configure_server_xml(keystore_path, keystore_pass, server_name)

    # Configure logging.properties
    configure_logging_properties(server_name)

    # Configure Tomcat Manager
    configure_tomcat_manager(org, tomcat_config['runtime_env'], server_name)

    # Configure Tomcat users
    configure_tomcat_manager_users(tomcat_config)


def configure_server_xml(keystore_path: str, keystore_pass: str, server_name: str):
    server_xml_path = os.environ['CATALINA_BASE'] + r'/conf/server.xml'

    with open(server_xml_path, 'r') as f:
        server_xml = f.read()

    # Modify the server.xml content based on the configuration
    # Add SSL Connector
    tls_port = os.environ['TC_SECURE_PORT']
    match_line = r'<Service name="Catalina">'
    connector = f"\n\n    <Connector port=\"{tls_port}\" maxThreads=\"200\" scheme=\"https\" \
    \n\t       secure=\"true\" SSLEnabled=\"true\" \
    \n\t       keystoreFile=\"{keystore_path}\" \
    \n\t       keystorePass=\"{keystore_pass}\" \
    \n\t       keyAlias=\"{server_name}\" \
    \n\t       sslEnabledProtocols=\"TLSv1.3\" \
    \n\t       clientAuth=\"false\" sslProtocol=\"TLS\" \
    \n\t       URIEncoding=\"UTF-8\" \
    \n\t       /> \
    \n"

    server_xml = re.sub(match_line, match_line + connector, server_xml)

    # Add URIEncoding to the HTTP Connector
    match_term = r'<Connector port="8080" protocol="HTTP/1.1"(.*?)maxParameterCount="1000"'
    append_term = r'\n\t           URIEncoding="UTF-8"'

    # Preview the match
    match = re.search(match_term, server_xml, re.DOTALL)
    #print(match.group(0))

    server_xml = re.sub(match_term, match.group(0) + append_term, server_xml, flags=re.DOTALL)

    # Update defaultHost in Engine
    match_term = r'<Engine name="Catalina" defaultHost="localhost">'
    replace_term = f'<Engine name="Catalina" defaultHost="{server_name}" jvmRoute="{os.environ["INSTANCE_NAME"]}">'

    # Preview the match
    #match = re.search(match_term, server_xml)
    #print(match.group(0))

    # Apply the change
    server_xml = re.sub(match_term, replace_term, server_xml)

    # Update Host to hostname
    match_term = r'<Host name="localhost"  appBase="webapps"'
    replace_term = f'<Host name="{server_name}"  appBase="webapps"'

    # Preview the match
    #match = re.search(match_term, server_xml)
    #print(match.group(0))

    # Apply the change
    server_xml = re.sub(match_term, replace_term, server_xml)

    # Update AccessLog prefix to instance name
    match_term = r'prefix="localhost_access_log" suffix=".txt"'
    replace_term = f'prefix="{os.environ["INSTANCE_NAME"]}-access-log" suffix=".txt"'

    # Preview the match
    #match = re.search(match_term, server_xml)
    #print(match.group(0))

    # Apply the change
    server_xml = re.sub(match_term, replace_term, server_xml)

    with open(server_xml_path, 'w') as f:
        f.write(server_xml)

    print("Server.xml configured.")


def configure_logging_properties(server_name: str):
    logging_properties_path = os.environ['CATALINA_BASE'] + r'/conf/logging.properties'
    instance_name = os.environ['INSTANCE_NAME']

    with open(logging_properties_path, 'r') as f:
        logging_properties = f.read()

    # Modify logging properties as needed
    # Update localhost to server name

    # Preview the match
    match_term = r'localhost'
    #match = re.findall(match_term, logging_properties)
    #print(match.group(0))

    # Apply the change
    logging_properties = re.sub(match_term, instance_name, logging_properties)

    # Update Catalina log file name
    match_term = r'(prefix = )(catalina\.)'
    replace_term = f'\\1{instance_name}-\\2'
    # Preview the match
    #match = re.findall(match_term, logging_properties)
    #print(match.group(0))

    # Apply the change
    logging_properties = re.sub(match_term, replace_term, logging_properties)

    # Update Manager log file name
    match_term = r'(prefix = )(manager\.)'
    replace_term = f'\\1{instance_name}-\\2'

    # Preview the match
    #match = re.findall(match_term, logging_properties)
    #print(match.group(0))

    # Apply the change
    logging_properties = re.sub(match_term, replace_term, logging_properties)

    # Update HostManager log file name
    match_term = r'(prefix = )(host-manager\.)'
    replace_term = f'\\1{instance_name}-\\2'

    # Preview the match
    #match = re.findall(match_term, logging_properties)
    #print(match.group(0))

    # Apply the change
    logging_properties = re.sub(match_term, replace_term, logging_properties)

    with open(logging_properties_path, 'w') as f:
        f.write(logging_properties)

    print("Logging.properties configured.")


def configure_tomcat_manager(org: str, runtime_env: str, server_name: str):
    # Set up Tomcat Manager application
    mgr_xml_dir = os.environ['CATALINA_BASE'] + f'/conf/Catalina/{server_name}'
    mgr_xml_path = os.environ['CATALINA_BASE'] + f'/conf/Catalina/{server_name}/manager.xml'

    mgr_xml_content = r"""<?xml version="1.0" encoding="UTF-8" ?>
<Context privileged="true" antiResourceLocking="false"
         docBase="${catalina.home}/webapps/manager">
<CookieProcessor className="org.apache.tomcat.util.http.Rfc6265CookieProcessor"
                 sameSiteCookies="strict" />
<Valve className="org.apache.catalina.valves.RemoteAddrValve"
       allow="127.\d+\.\d+\.\d+|192.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />
<Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
    """

    if not os.path.isdir(mgr_xml_dir):
        os.makedirs(mgr_xml_dir)

    with open(mgr_xml_path, 'w') as f:
        f.write(mgr_xml_content)

    # Brand Tomcat Manager 
    manager_web_xml_path = os.environ['CATALINA_HOME'] + r'/webapps/manager/WEB-INF/web.xml'

    with open(manager_web_xml_path, 'r') as f:
        manager_web_xml = f.read()

    # Modify Sub-Title
    match_term = r'(<param-value>)Sub-Title(</param-value>)'
    replace_term = r'\1' + f'<br><i style="color:GoldenRod">{org} {runtime_env} - Apache TomcatManager</i></br>' + r'\2'

    # Preview the match
    #match = re.search(match_term, manager_web_xml)
    #print(match.group(0))

    # Apply the change
    manager_web_xml = re.sub(match_term, replace_term, manager_web_xml)

    # Uncomment Sub-Tile parameter
    # <!-- Uncomment this to set a sub-title for the manager web application main
    #     page. It must be XML escaped, valid HTML.
    #<init-param>
    #  <param-name>htmlSubTitle</param-name>
    #  <param-value><br><i style="color:GoldenRod">Avium Labs Development Manager</i></param-value>
    #</init-param>
    #-->
    match_term = r'(<!-- Uncomment this to set a sub-title.*)(<init-param>.*?htmlSubTitle.*?</init-param>).*?-->'
    replace_term = r'\1-->\n    \2'

    # Preview the match
    match = re.search(match_term, manager_web_xml, re.DOTALL)
    #print(match.group(0))

    # Apply the change
    manager_web_xml = re.sub(match_term, replace_term, manager_web_xml, flags=re.DOTALL)

    # Update web.xml file
    with open(manager_web_xml_path, 'w') as f:
        f.write(manager_web_xml)

    print("Tomcat Manager configured.")


def configure_tomcat_manager_users(tomcat_config: dict):
    tomcat_users_xml_path = os.path.join(os.environ['CATALINA_BASE'], 'conf', 'tomcat-users.xml')
    mgr_pass_path = os.path.join(os.environ['SECRETS_HOME'], tomcat_config['managerpass'])
    rpa_pass_path = os.path.join(os.environ['SECRETS_HOME'], tomcat_config['rpapass'])
    jmx_pass_path = os.path.join(os.environ['SECRETS_HOME'], tomcat_config['jmxpass'])

    mgr_pass_file = os.environ['MGR_PASS_FILE']
    rpauser_pass_file = os.environ['RPAUSER_PASS_FILE']
    jmxuser_pass_file = os.environ['JMXUSER_PASS_FILE']

    if mgr_pass_file:
        mgr_pass_path = mgr_pass_file

    if rpauser_pass_file:
        rpa_pass_path = rpauser_pass_file

    if jmxuser_pass_file:
        jmx_pass_path = jmxuser_pass_file

    # Set default passwords
    manager = tomcat_config['manager']
    rpauser = tomcat_config['rpauser']
    jmxuser = tomcat_config['jmxuser']

    if os.path.isfile(mgr_pass_path):
        with open(mgr_pass_path, 'r') as f:
            managerpass = f.read().strip()
    else:
        managerpass = gen_random_password()
        with open(mgr_pass_path, 'w') as f:
            f.write(managerpass)

    if os.path.isfile(rpa_pass_path):
        with open(rpa_pass_path, 'r') as f:
            rpapass = f.read().strip()
    else:
        rpapass = gen_random_password()
        with open(rpa_pass_path, 'w') as f:
            f.write(rpapass)

    if os.path.isfile(jmx_pass_path):
        with open(jmx_pass_path, 'r') as f:
            jmxpass = f.read().strip()
    else:
        jmxpass = gen_random_password()
        with open(jmx_pass_path, 'w') as f:
            f.write(jmxpass)

    with open(tomcat_users_xml_path, 'r') as f:
        tomcat_users_xml = f.read()

    match_admin = r'(<user username=\")admin(\" password=\").*?(\".*?/>)'
    replace_admin = f'\\1{manager}\\2{managerpass}\\3'

    # Preview the match
    #match = re.search(match_admin, tomcat_users_xml)

    # Apply the change
    tomcat_users_xml = re.sub(match_admin, replace_admin, tomcat_users_xml)

    # Add JMX user
    match_robot = r'(<user username=")robot(" password=").*?(".*?/>)'
    replace_robot = f'\\1{rpauser}\\2{rpapass}\\3'
    append_jmx = f'\n  <user username="{jmxuser}" password="{jmxpass}" roles="manager-jmx"/>'

    # Preview the match
    #match = re.search(match_robot, tomcat_users_xml)
    #print(match.group(0))

    # Apply the change
    tomcat_users_xml = re.sub(match_robot, replace_robot + append_jmx, tomcat_users_xml)

    # Uncomment users
    match_term = r'(<!--?[\s]*<user username="manager".*?roles="manager-jmx"/>.*?-->)'
    replace_term = lambda m: m.group(0).replace('<!--', '').replace('-->', '')

    # Preview the match
    #match = re.search(match_term, tomcat_users_xml, re.DOTALL)
    #print(match.group(0))

    # Apply the change
    tomcat_users_xml = re.sub(match_term, replace_term, tomcat_users_xml, flags=re.DOTALL)

    # Update tomcat-users.xml
    with open(tomcat_users_xml_path, 'w') as f:
        f.write(tomcat_users_xml)

    print("Tomcat users configured.")


def gen_random_password(length: int = 16) -> str:
    characters = string.ascii_letters + string.digits
    password = ''.join(random.choice(characters) for i in range(length))

    return password


def parse_config():
    conf_file = os.environ['SECRETS_HOME'] + r'/tomcat.config'
    parser = configparser.ConfigParser()
    parser.read(conf_file)

    tomcat_config = {}

    if 'tomcat' in parser:
        tomcat_config = dict(parser['tomcat'])

    keystore_config = {}

    if 'keystore' in parser:
        keystore_config = dict(parser['keystore'])

    return tomcat_config, keystore_config


def save_config(tomcat_config: dict, keystore_config: dict):
    conf_file = os.environ['SECRETS_HOME'] + r'/tomcat.config'

    parser = configparser.ConfigParser()
    parser['tomcat'] = tomcat_config
    parser['keystore'] = keystore_config

    with open(conf_file, 'w') as configfile:
        parser.write(configfile)


if __name__ == "__main__":
    main()