#!/bin/sh

[ -n /root/backup/openshift ] && mkdir -p /root/backup/openshift
cd /root/backup/openshift
DATE=`date +%Y%m%d.%H`
DIR=/root/backup/openshift/$DATE

# Backup object per project for easy restore
mkdir -p $DIR/projects
cd $DIR/projects
for i in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do 
  mkdir $i
  cd $i
  oc export namespace $i >ns.yml
  oc export project   $i >project.yml
  for j in pods replicationcontrollers deploymentconfigs buildconfigs services routes pvc quota hpa secrets configmaps daemonsets deployments endpoints imagestreams ingress jobs limitranges policies policybindings roles rolebindings resourcequotas replicasets serviceaccounts templates oauthclients petsets
  do 
    mkdir $j
    cd $j
    for k in `oc get $j -n $i --no-headers |awk '{print $1}'`
    do
      echo export $j $k '-n' $i
      oc export $j $k -n $i >$k.yml
    done
    cd ..
  done
  cd ..
done

mkdir -p $DIR/global
cd $DIR/global
for j in cluster clusternetwork clusterpolicy clusterpolicybinding clusterresourcequota clusterrole clusterrolebinding egressnetworkpolicy group hostsubnet identity netnamespace networkpolicy node persistentvolumes securitycontextconstraints thirdpartyresource thirdpartyresourcedata user useridentitymapping
do 
  mkdir $j
  cd $j
  for k in `oc get $j -n $i --no-headers |awk '{print $1}'`
  do
    echo export $j $k '-n' $i
    oc export $j $k -n $i >$k.yml
  done
  cd ..
done

cd $DIR
# etcd database backup
etcdctl backup --data-dir /var/lib/openshift/openshift.local.etcd   --backup-dir etcd

# config files backup
mkdir files
rsync -va /etc/ansible/facts.d/openshift.fact \
          /etc/atomic-enterprise \
          /etc/corosync \
          /etc/ansible \
          /etc/etcd \
          /etc/openshift \
          /etc/openshift-sdn \
          /etc/origin \
          /etc/sysconfig/atomic-enterprise-master \
          /etc/sysconfig/atomic-enterprise-node \
          /etc/sysconfig/atomic-openshift-master \
          /etc/sysconfig/atomic-openshift-master-api \
          /etc/sysconfig/atomic-openshift-master-controllers \
          /etc/sysconfig/atomic-openshift-node \
          /etc/sysconfig/openshift-master \
          /etc/sysconfig/openshift-node \
          /etc/sysconfig/origin-master \
          /etc/sysconfig/origin-master-api \
          /etc/sysconfig/origin-master-controllers \
          /etc/sysconfig/origin-node \
          /etc/systemd/system/atomic-openshift-node.service.wants \
          /root/.kube \
          $HOME/.kube \
          /root/.kubeconfig \
          $HOME/.kubeconfig \
          /usr/lib/systemd/system/atomic-openshift-master-api.service \
          /usr/lib/systemd/system/atomic-openshift-master-controllers.service \
          /usr/lib/systemd/system/origin-master-api.service \
          /usr/lib/systemd/system/origin-master-controllers.service \
      files

# compress
cd $DIR/..
tar czvf ${DATE}.tgz $DATE
rm -rf $DATE
