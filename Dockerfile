# Transmart 1.2 using hyve installatiion
# cf https://wiki.transmartfoundation.org/pages/viewpage.action?pageId=6619205
FROM ubuntu:14.04
MAINTAINER Karl Forner <karl.forner@gmail.com>


### STEP 1
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv 3375DA21 && \
	echo deb http://apt.thehyve.net/internal/ trusty main | \
	tee /etc/apt/sources.list.d/hyve_internal.list && apt-get update

### STEP 2
RUN apt-get install -y \
	make                    \
	curl                    \
	git                     \
	openjdk-7-jdk           \
	groovy                  \
	php5-cli                \
	php5-json               \
	postgresql-9.3          \
	apache2                 \
	tomcat7                 \
	libtcnative-1           \
	transmart-r

# ==================== setup USER transmart ====================
# create home too
RUN useradd -m transmart
# sudo with no password
RUN echo "transmart ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
ENV HOME /home/transmart

USER transmart
WORKDIR /home/transmart

### STEP 3: transmart-data
RUN git clone --progress https://github.com/transmart/transmart-data.git &&  \
	cd transmart-data && git checkout tags/v1.2.0

### STEP 4 and 5: configure transmart-data and create the db
WORKDIR /home/transmart/transmart-data

## Configure default locale: TODO, put it below, before transmart
RUN sudo bash -c 'echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
	&& locale-gen en_US.utf8 \
	&& /usr/sbin/update-locale LANG=en_US.UTF-8'
ENV LC_ALL en_US.UTF-8

RUN php env/vars-ubuntu.php > vars
RUN sudo service postgresql start && \
	 sudo -u postgres bash -c \
	 "source vars; PGSQL_BIN=/usr/bin/ PGDATABASE=template1 make -C ddl/postgres/GLOBAL tablespaces" \
	&& bash -c "source vars && make postgres"

### STEP 6: Copy tranSMART configuration files
RUN sudo bash -c "source vars; TSUSER_HOME=/usr/share/tomcat7/ make -C config/ install"

### STEP 7: Install and run solr
#  karl: N.B, modified to only install
RUN sudo bash -c "source vars; make -C solr/ solr_home"

### STEP 8: Configure and start Rserve
#  karl: N.B, will just configure it for now
RUN echo 'USER=tomcat7' | sudo tee /etc/default/rserve
#sudo service rserve start

### STEP 9: Deploy tranSMART web application on tomcat.
RUN sudo service tomcat7 stop && \
	echo 'JAVA_OPTS="-Xmx4096M -XX:MaxPermSize=1024M"' | sudo tee /usr/share/tomcat7/bin/setenv.sh
#sudo service tomcat7 start

### STEP 10: Prepare ETL environment
RUN bash -c 'source vars && \
	make -C env/ data-integration && \
	make -C env/ update_etl'

### STEP 11:  example studies
# karl: fix, must update the git repo first and re-run data-integration
RUN git pull origin master && \
	bash -c 'source vars && make -C env/ data-integration'

# karl: need xz-utils
RUN sudo apt-get install xz-utils
#RUN sudo service postgresql start && bash -c 'source vars && \
#	make -C samples/postgres load_clinical_GSE8581 load_ref_annotation_GSE8581 \
#	load_expression_GSE8581 load_analysis_GSE8581'

RUN sudo service postgresql start && bash -c 'source vars && \
	make -C samples/postgres load_clinical_GSE8581'

RUN sudo service postgresql start && bash -c 'source vars && \
	make -C samples/postgres load_ref_annotation_GSE8581'

RUN sudo service postgresql start && bash -c 'source vars && \
	make -C samples/postgres load_expression_GSE8581'

#RUN sudo service postgresql start && bash -c 'source vars && \
#	make -C samples/postgres load_analysis_GSE8581'

EXPOSE 8080

### make a startup script for Rserve
RUN bash -c 'echo "/opt/R/bin/R CMD Rserve --quiet --vanilla --RS-conf \
	/etc/Rserve.conf > /tmp/rserve.out 2>/tmp/rserve.err &" > ./rserve.sh' && \
	 chmod a+rx ./rserve.sh

### ERRATUM: transmart webapp
RUN sudo apt-get install -y wget
RUN echo 'JAVA_OPTS="-Xmx4096M -XX:MaxPermSize=1024M"' | \
	sudo tee /usr/share/tomcat7/bin/setenv.sh && \
	sudo wget -P /var/lib/tomcat7/webapps/ https://ci.transmartfoundation.org/browse/SAND-TRAPP/latest/artifact/shared/transmart.war/transmart.war



CMD sudo service postgresql start && \
	sudo -u tomcat7 bash  ./rserve.sh && \
	sudo service tomcat7 start; \
	sudo bash -c 'source vars && make -C solr/ start'
