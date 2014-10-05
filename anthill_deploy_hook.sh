# $1 = path
# $2 = build
# $3 = package
# $4 = job type
# $5 = current working directory
P=$(/bin/pwd)
/opt/netcool/wfperlexe/bin/perl anthill_deploy.pl $1 $2 $3 $4 $P
c=$?
if [ "$c" -ne "0" ]; then
  echo "failed with return code: $c"
  exit 1
else
  echo "success return code"
  exit 0
fi
