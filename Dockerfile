FROM nvidia/cuda:10.1-devel-centos7
MAINTAINER Michael Gorkow <michael.gorkow@sas.com>

# Add users and set passwords
RUN useradd -U -m sas && useradd -g sas -m cas
RUN echo "Orion123" | passwd root --stdin && echo "Orion123" | passwd sas --stdin && echo "Orion123" | passwd cas --stdin

# set ulimit values
RUN echo "*     -     nofile     65536" >> /etc/security/limits.conf && echo "*     -     nproc      65536" >>/etc/security/limits.d/90-nproc.conf

# Install prereq packages
RUN yum -y update && yum install -y epel-release && yum install -y gcc wget git python-devel java-1.8.0-openjdk glibc libpng12 libXp libXmu numactl xterm initscripts which iproute sudo httpd mod_ssl && yum -y install openssl unzip openssh-clients bind-utils openssl-devel deltarpm libffi-devel net-tools sudo \
	&& yum -y groupinstall "Development Tools" \
	&& yum clean all

# Install ansible
RUN wget https://bootstrap.pypa.io/get-pip.py && python get-pip.py && pip install ansible==2.7.12

# Ansible known hosts
RUN mkdir ~/.ssh && touch ~/.ssh/known_hosts

# Add deployment data zip to directory
RUN mkdir -p /opt/sas/installfiles
WORKDIR /opt/sas/installfiles
ADD SAS_Viya_deployment_data.zip /opt/sas/installfiles

# Get orchestration tool and install.  Then build and untar playbook
############################################ Modified Frederik  ##################
ADD  sas-orchestration /opt/sas/installfiles
RUN /opt/sas/installfiles/sas-orchestration build --platform redhat --deployment-type programming --input SAS_Viya_deployment_data.zip --repository-warehouse http://10.132.0.20:9125/  && tar xvf SAS_Viya_playbook.tgz
WORKDIR /opt/sas/installfiles/sas_viya_playbook
RUN mv /opt/sas/installfiles/sas_viya_playbook/inventory.ini /opt/sas/installfiles/sas_viya_playbook/inventory.ini.orig
RUN cp /opt/sas/installfiles/sas_viya_playbook/samples/inventory_local.ini /opt/sas/installfiles/sas_viya_playbook/inventory.ini
###################################################################################

# Deploy with ansible; remove httpd start error
RUN sed -i "/ notify/,+9d" roles/httpd-x64_redhat_linux_6-yum/tasks/configure-and-start.yml && \
	sed -i "s/- include: validate/#/" internal/deploy-preinstall.yml && \
	ansible-playbook site.yml -vvv && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.hosts && \ 
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/casconfig_deployment.lua && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.yml && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.hosts.tmp && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/batchserver/default/autoexec_deployment.sas && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/sysconfig/cas/default/sas-cas-deployment && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/sysconfig/cas/default/cas_grid_vars && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/workspaceserver/default/autoexec_deployment.sas && \
	sed -i "s/$(hostname)/localhost/g" /etc/httpd/conf.d/proxy.conf
	# sed -i "s/\${ADMIN_USER}/sas/g" /opt/sas/viya/config/etc/cas/default/perms.xml


# Add start script 
ADD start.sh /opt/sas/installfiles
RUN chmod +x /opt/sas/installfiles/start.sh

# Install anaconda
RUN yum install -y wget bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    git mercurial subversion && yum clean all

RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/archive/Anaconda3-5.0.1-Linux-x86_64.sh -O ~/anaconda.sh && \
    /bin/bash ~/anaconda.sh -b -p /opt/conda && \
    rm ~/anaconda.sh

ENV PATH /opt/conda/bin:$PATH

# Install python packages with anaconda
RUN conda install -c conda-forge opencv -y \
	&& conda install -c anaconda seaborn -y \
	&& conda install -c conda-forge sas_kernel -y \
	&& conda install -c anaconda pillow -y \
	&& conda install -c conda-forge matplotlib -y \
	&& conda install -c anaconda graphviz -y \
	&& conda install -c conda-forge python-graphviz -y 

# Install swat, opencv (conda install does not seem to work)
RUN pip install https://github.com/sassoftware/python-swat/releases/download/v1.6.0/python-swat-1.6.0-linux64.tar.gz && pip install opencv-python && pip install sas-dlpy

# Configure jupyter
RUN pip install jupyterlab && \
	jupyter notebook --generate-config --allow-root && \
	echo "c.NotebookApp.token = u''" >> /root/.jupyter/jupyter_notebook_config.py && \
	echo "c.NotebookApp.ip = '*'" >> /root/.jupyter/jupyter_notebook_config.py && \
	echo "c.NotebookApp.notebook_dir = '/data'" >> /root/.jupyter/jupyter_notebook_config.py



# Create homepage
RUN touch /var/www/html/index.html && printf "%s" "<h1>Welcome to SAS ESP DeepLearn Docker</h1>" >> /var/www/html/index.html
# Expose ports for Studio, CAS controller, and jupyter

EXPOSE 80
EXPOSE 5570
EXPOSE 8888
# Calls start script (starts httpd and sas-viya-all-services, then sleeps)
RUN pip install git+https://github.com/sassoftware/python-dlpy.git@master --upgrade
RUN pip install "pandas==0.25.3"
CMD /opt/sas/installfiles/start.sh

