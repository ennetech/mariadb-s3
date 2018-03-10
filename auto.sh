#!/usr/bin/env bash

mc config host add srv $S3_SERVER $S3_USER $S3_PASSWORD

#mc rm --force -r "srv/$S3_BUCKET"

BUCKET_SERVICE=srv/$S3_BUCKET
BUCKET_ROOT=$BUCKET_SERVICE/_current/
LOCK_FILE="$BUCKET_ROOT""_lock"

WORK_DIR=/tmp/tmp_docker_sql

DBLIST_FILE=$WORK_DIR/_databases

info(){
  echo "(i) $@"
}

_lock () {
  mkdir -p $WORK_DIR
  printenv > $WORK_DIR/_lock
  mc cp $WORK_DIR/_lock $LOCK_FILE
}

_dump(){
  MYSQL_USER=root
  MYSQL_PASS=$MYSQL_ROOT_PASSWORD
  MYSQL_CONN="-u${MYSQL_USER} -p${MYSQL_PASS}"

  SQL="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN"
  SQL="${SQL} ('mysql','information_schema','performance_schema')"

  mysql ${MYSQL_CONN} -ANe"${SQL}" > ${DBLIST_FILE}

  MYSQLDUMP_OPTIONS="--routines --triggers --single-transaction"
  for DB in `cat ${DBLIST_FILE}` ; do 
    echo "Processing: $DB"
    mysqldump ${MYSQL_CONN} ${MYSQLDUMP_OPTIONS} --databases ${DB} > $WORK_DIR/$DB.sql
  done
}

# Waits for server to start, then scans the $WORK_DIR in search of sql files
_restore(){
  while ! mysqladmin ping --silent; do
    info "Waiting..."
    sleep 1
  done
  sleep 5
  info "Server ready, restoring backup..."
  FILES=$(find $WORK_DIR -name "*.sql" -type f -maxdepth 1)
  info "Found files: $FILES"
  for f in $FILES
  do
  info ">> $f (importing)"
  mysql -u root -p$MYSQL_ROOT_PASSWORD < $f
  info "-- $f (import file deleted)"
  rm $f
  done
  info "...restored"
  _daemon &
}

_save() {
  rm $DBLIST_FILE
  mc cp -r "$WORK_DIR/" $BUCKET_ROOT
}

_unlock() {
  #info "Making snapshot before unlocking..."
  #HHH="$(date +"%Y%m%d_%H%M%S")-$(hostname)"
  #mc cp -r "$WORK_DIR/" $BUCKET_SERVICE/$HHH/
  mc rm $LOCK_FILE
}

_daemon() {
  while true; do
    sleep $BACKUP_INTERVAL
    info "Daemon here..."
    _dump
    _save
    info "... daemon done"
  done
}

# Upon closing we have to store one last backup
_term() {
  info "Closing signal received, current databases:"
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"
  info "Dumping to workdir"
  _dump
  info "Saving workdir to bucket"
  _save
  info "Unlocking bucket"
  _unlock
  kill -TERM "$child" 2>/dev/null # Could use kill :)
}

# Precondition
info "Checking for lock"
mc stat $LOCK_FILE
if [ "$?" -eq 0 ];then
    echo "Bucket is locked, exiting. Ensure there aren't any other istance and remove _lock file from bucket root"
    exit
fi

trap _term SIGINT SIGTERM

# Preparation
info "Obtaining lock"
_lock
info "Downloading from bucket"
mc cp -r $BUCKET_ROOT $WORK_DIR/
info "Starting restore process"
_restore &

info "Launching server normally"
# Main command
docker-entrypoint.sh mysqld &
          
child=$!
wait "$child"

# Cleanup
echo "Bye bye!!!"
