#!/bin/sh

DATE=`date +%Y%m%d.%H`
DIR=/var/backup/openshift
DEPLOYMENT_TYPE="atomic-openshift"
DEPLOYMENT_TYPE="origin"

cd $DIR && git status 2>/dev/null
[ $? != 0 ] && DIR=$DIR/$DATE

# Backup object per project for easy restore
mkdir -p $DIR/projects
cd $DIR/projects
for i in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do 
  mkdir $i
  cd $i
  oc export namespace $i >ns.yml
  oc export project   $i >project.yml
  for j in pods replicationcontrollers deploymentconfigs buildconfigs services routes pvc quota hpa secrets configmaps daemonsets deployments endpoints imagestreams ingress cronjobs jobs limitranges policies policybindings roles rolebindings resourcequotas replicasets serviceaccounts templates oauthclients statefullsets
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
for j in cluster clusternetwork clusterpolicy clusterpolicybinding clusterresourcequota clusterrole clusterrolebinding egressnetworkpolicy group hostsubnet identity netnamespace networkpolicy node persistentvolumes securitycontextconstraints customresourcedefinition user useridentitymapping
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
etcdctl snapshot save etcd_snapshot.db

# config files backup
mkdir master-config
rsync -va /etc/ansible/facts.d/openshift.fact \
          /etc/ansible \
          /etc/etcd \
          /etc/openshift-sdn \
          /etc/origin \
          /etc/sysconfig/$DEPLOYMENT_TYPE-master \
          /etc/sysconfig/$DEPLOYMENT_TYPE-master-api \
          /etc/sysconfig/$DEPLOYMENT_TYPE-master-controllers \
          /etc/sysconfig/$DEPLOYMENT_TYPE-node \
          /etc/systemd/system/$DEPLOYMENT_TYPE-node.service.wants \
          /root/.kube \
          $HOME/.kube \
          /root/.kubeconfig \
          $HOME/.kubeconfig \
          /usr/lib/systemd/system/$DEPLOYMENT_TYPE-master-api.service \
          /usr/lib/systemd/system/$DEPLOYMENT_TYPE-master-controllers.service \
          /var/lib/etcd \
      master-config/

### Persistent Data ###
oc observe  --all-namespaces --once pods     \
  -a '{ .metadata.labels.deploymentconfig }' \
  -a '{ .metadata.labels.technology }'       \
  -a '{ .metadata.labels.backup     }'       \
 |while read IGNORE1 IGNORE2 IGNORE3 IGNORE4 IGNORE5 PROJECT POD DC TECH SCHEDULE
do
    [ "$SCHEDULE" == "\"\"" -o "$SCHEDULE" == "" ] && continue
    [ "$DC" == "\"\"" ] && DC=$POD
    echo "$POD in $PROJECT wants a $TECH $SCHEDULE backup"
    mkdir -p $DIR/$TECH/$PROJECT  2>/dev/null
    cd       $DIR/$TECH/$PROJECT
    case $TECH in
      mysql)
        oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'PATH=$PATH:/opt/rh/mysql55/root/usr/bin:/opt/rh/rh-mysql56/root/usr/bin/ mysqldump -h 127.0.0.1 -u $MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE' >$DC.sql
        ;;
      postgresql)
        oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'PATH=$PATH:/opt/rh/rh-postgresql94/root/usr/bin:/opt/rh/rh-postgresql95/root/usr/bin pg_dump $POSTGRESQL_DATABASE' >$DC.sql
        ;;
      file)
        [ "$DC" == "$POD" ] && OBJ="pod/$POD" || OBJ="dc/$DC"
        MOUNTS=`oc -n $PROJECT volume $OBJ |egrep -i "hostPath|pvc" -A1 |grep "mounted at" |awk '{print $3}'`
        for MOUNT in $MOUNTS; do
          mkdir -p $OBJ/$MOUNT
          oc -n $PROJECT rsync $POD:$MOUNT $OBJ/$MOUNT
        done
        ;;
      *)
        echo "Unknown technology: '$TECH'. Possible values: mysql, postgresql, file."
        ;;
    esac
done


cd $DIR
git status 2>/dev/null
if [ $? == 0 ]; then
  git add .
  git commit -am "$DATE"
  git push -u origin master
else
  # compress
  cd $DIR/..
  tar czf ${DATE}.tgz $DATE
  echo rm -r $DATE
fi
