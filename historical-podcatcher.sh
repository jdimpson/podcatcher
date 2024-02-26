#!/bin/bash

ME=`basename "$0"`;
VER="0.1";
MYHOME="$HOME/podcatcher";
PYX="/usr/local/bin/xml pyx";
SEL="/usr/local/bin/xml sel";
SQLITE="sqlite3";
CURL="curl";
CURLCONF="$MYHOME/curlrc"
PODDB="$MYHOME/podcatcher.sqlite"
DBVER=1
DEBUG=0
HELP=0
QUIET=0
CATCHUP=0
TMPFILE1=`mktemp ./.$ME-tmpprocess-$$-XXXXXXX`;
TMPFILE2=`mktemp ./.$ME-tmpprocess-$$-XXXXXXX`;
trap 'if test -e "$TMPFILE1"; then rm -f "$TMPFILE1"; fi; if test -e "$TMPFILE2"; then rm -f "$TMPFILE2"; fi;'  EXIT
trap 'exit 4' INT

makepoddbV1() {
	test "$DEBUG" -gt 0 && echo "Creating databases" >&2;
	$SQLITE $PODDB 'CREATE TABLE schemaver (version INTEGER);'
	$SQLITE $PODDB "insert into schemaver (version) values ($DBVER) "
	$SQLITE $PODDB 'create table podcasts(castid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,castname TEXT NOT NULL,feedurl TEXT NOT NULL UNIQUE, pcenabled INTEGER NOT NULL DEFAULT 1, lastupdate INTEGER, lastattempt INTEGER, failedattempts INTEGER NOT NULL DEFAULT 0);'
	$SQLITE $PODDB 'CREATE TABLE episodes (castid INTEGER NOT NULL, episodeid INTEGER NOT NULL, title TEXT NOT NULL, epurl TEXT NOT NULL, enctype TEXT NOT NULL,status TEXT NOT NULL, eplength INTEGER NOT NULL DEFAULT 0, epfirstattempt INTEGER, eplastattempt INTEGER, epfailedattempts INTEGER NOT NULL DEFAULT 0,UNIQUE(castid, epurl),UNIQUE(castid, episodeid));'
	
}

getdbver() {
	$SQLITE $PODDB 'select * from schemaver;'
}

rssscrub() {
	local URL;
	URL="$1";   # if ever need to do per podcast scrubbing
	cat |\
	sed \
		-e 's/&\([^;]*\) /\&amp;\1/'\
		-e 's/\xCE\xA0//g'\
		-e 's/\xC2\xA9//g'\
		-e 's/\xC2\xA0//g'\
		-e 's/\xC2\x9D//g'\
		-e 's/\xA0//g'\
		-e 's/\xC2//g';
}

usage() {
	echo "Usage: $me [-hdq] (add podcastURL | update | catchup | list)"
}

getchanneltitle() {
	sed -n -e '1,/(item/p' | sed -n -e '/(image/,/)image/!p' | sed -n -e '/(title/,/)title/p' | grep -v '^[)(]title$' | sed -e 's/^-//' | sed -e ':a;N;$!ba;s/\n//g'
}

isrss () {
	local F;
	F="$1";
	if file "$F" | grep -q "XML  document text"; then
		return 0;
	fi
	if file "$F" | grep -q "ASCII English text, with very long lines"; then
		# Seems to happen when the opening tag has lots of xmlns attribs
		# this seems to have priority over XML in the magic file.
		if grep -qi "<rss" "$F"; then
			return 0;
		fi
	fi
	return 1; #XXX: could be more thorough
}

addpodcast() {
	local URL;
	URL="$1";
	$CURL --user-agent "$ME/$VER" --config $CURLCONF "$URL" > $TMPFILE1
	if ! isrss "$TMPFILE1"; then
		echo "$URL is not RSS" >&2
		echo -1 ; # becomes castid
		return; 
	fi
	rssscrub < $TMPFILE1 | $PYX > $TMPFILE2
	title=`getchanneltitle < $TMPFILE2`;
	test "$DEBUG" -gt 0 && echo "Title of $URL is $title" >&2
	ID=`$SQLITE $PODDB "select castid from podcasts where feedurl = '$URL';"`
	if test -z "$ID"; then
		test "$DEBUG" -gt 0 && echo "$URL is new, adding to database" >&2;
		title=`sqlescape "$title"`;	
		$SQLITE $PODDB "insert into podcasts (castname,feedurl) values ('$title','$URL');"
		ID=`$SQLITE $PODDB "select castid from podcasts where feedurl = '$URL';"`;
	else
		test "$DEBUG" -gt 0 && echo "$URL was already in database" >&2;
		ID=0;
	fi
	echo "$ID";
}

getpodcasts() {
	# returns space/newline separated list of "ID|URL|TITLE"
	$SQLITE $PODDB "select castid, feedurl, castname from podcasts;";
}

listcasts () {
	getpodcasts | while read line; do
		id=`dbresultcol 1 "$line"`;
		url=`dbresultcol 2 "$line"`;
		tit=`dbresultcol 3 "$line"`;
		echo "$id	$tit	$url";
	done
}

dbresultcol() {
	local COLNUM;
	local DBRESULT;
	COLNUM="$1"; DBRESULT="$2";
	echo "$DBRESULT" | awk -F '|' "{ print \$$COLNUM } "
}

seen() {
	local URL
	URL="$1"

	numseen=`$SQLITE $PODDB "select count(*) from episodes where epurl = '$URL';"`;
	if test "$numseen" -le 0; then
		return 1;
	else
		return 0;
	fi
}

title2filename () {
	local TITLE;
	TITLE="$1";
	echo "$TITLE" | sed -e 's/\xA0//g' -e "s/'//g" -e "s/\xC2\xBB/-/g" -e 's/^-//' -e 's/://g' -e 's/^ *//' -e 's/ *$//';
}

url2filename () {
	local URL
	URL="$1";
	file=`basename "$URL"`;
	echo "$file" | sed -e 's/\xA0//g' -e "s/'//g" -e "s/%20/ /g";
}

downloadepisode () {
	local URL;
	local DIR;
	local DATE;
	local LENGTH;
	URL="$1"; DIR="$2"; DATE="$3"; LENGTH="$4"
	file=`url2filename "$URL"`;
	
	if test "$CATCHUP" -gt 0; then
		test "$DEBUG" -gt 0 && echo "skipping download of $URL" >&2;
		return 0;
	fi

	echo "downloading $URL into $DIR/$file";
	tf=`mktemp ./$ME-tmpmediadl-$$-XXXXXXX`;
	$CURL  --user-agent "$ME/$VER" --config $CURLCONF -o "$tf" "$URL" 
	if test -s "$tf"; then
		touchdate=`date -d "$DATE" +"%Y%m%d%H%M"`;
		mkdir "$DIR" > /dev/null 2>&1
		mv "$tf" "$DIR/$file";
		touch -t $touchdate "$DIR/$file"; # lets you sort by date; handy when grabbing new podcast with big backlog but no sane file numbering scheme.
		dlsize=`stat -c "%s" "$DIR/$file"`;
		dlsize=`expr "$dlsize" / 1024`;
		test "$DEBUG" -gt 0 && echo "given size: $LENGTH; dl size: $dlsize" >&2;
		return 0;
	fi

	rm "$tf";
	return 1; # fail
}

sqlescape () {
	local STR;
	STR="$1";
	echo "$STR" | sed -e "s/'/''/g"
}

markdownloaded () {
	local CAST;
	local URL;
	local TITLE;
	local TYPE;
	local LENGTH;
	CAST="$1"; URL="$2"; TITLE="$3"; TYPE="$4"; LENGTH="$5";
	TITLE=`sqlescape "$TITLE"`;

	status="Downloaded";
	maxid=`$SQLITE $PODDB "SELECT MAX(episodeid) FROM episodes WHERE castid = '$CAST';"`
	test -z "$maxid" && maxid=0;
	nextid=`expr "$maxid" + 1`;
	$SQLITE $PODDB "insert INTO episodes (castid, episodeid, title,epurl, enctype, status, eplength, epfirstattempt, eplastattempt) values ($CAST,$nextid,'$TITLE','$URL','$TYPE','$status','$LENGTH',datetime(),datetime());"
}

checkpodcast() {
	local ID;
	local URL;
	local TITLE;
	ID="$1"; URL="$2"; TITLE="$3";
	local OUTDIR;
	OUTDIR=`title2filename "$TITLE"`;
	test "$DEBUG" -gt 0 && echo TITLE is "$TITLE", OUTDIR is "$OUTDIR" >&2

	$CURL --user-agent "$ME/$VER" --conf $CURLCONF "$URL"| rssscrub "$URL" > $TMPFILE2
	if ! isrss "$TMPFILE2"; then
		echo "$URL is not RSS"; >&2
		return;
	fi

	ITEMCNT=`$SEL -t -v 'count(//item)' < $TMPFILE2`;
	if test -z "$ITEMCNT" || test "$ITEMCNT" -le 0; then
		test "$DEBUG" -gt 0 && echo "Couldn't find any items in $URL" >&2;
		return
	fi
	# not very efficient but can't think of another easy way to chunk up each item for individual processing
	for i in `seq 1 $ITEMCNT`; do
		$SEL -t -m "//item[$i]" -c '.' -n < $TMPFILE2 |\
		$SEL -t -m "item" -v "pubDate" -o "|" -v "title" -m "enclosure" -o "|" -v "@type" -o "|" -v "@length" -o "|" -v "@url" -b |\
		( IFS="|";
		while read date title type length url; do
			if test -z "$url"; then
				test "$DEBUG" -gt 0 && echo "no enclosure found in $title $date" >&2;
				break;
			fi
			if seen "$url"; then
				test "$DEBUG" -gt 0 && echo "previously downloaded $title $date $url" >&2;
				break;
			fi
			
			if downloadepisode "$url" "$OUTDIR" "$date" "$length"; then
				markdownloaded "$ID" "$url" "$title" "$type" "$length"
			else
				echo "Failed to download $TITLE episode $title ($url)" >&2
				# could do "markdownloaderror" here
				break;
			fi
		done
		)

	done
}

delicious () {
	USER=jdimpson
	PASS=XXXX
	if [ -z "$HPODDER_DELICIOUS" ]; then
        	HPODDER_DELICIOUS="https://${USER}:${PASS}@api.del.icio.us/v1/posts/all?tag=hpodder"
	fi
	$CURL --user-agent "$ME/$VER" --config $CURLCONF "$HPODDER_DELICIOUS" |\
	xmlstarlet sel -t -m '//post' -v '@href' \
          -o ' | ' -v '@description' \
          -o ' | ' -v '@extended' -n |\
        sed -e 's/amp;//g' |\
        grep -v '^$' | sort
}

# handle how we were invoked
CMD="none";
while [ ! -z "$1" ]; do
	case "$1" in
		"add") CMD="add"; ADDURL=$2; if test -z "$ADDURL"; then (echo "URL to add required"; usage) >&2; exit 2; fi; shift;;
		"update") CMD="update";;
		"catchup") CMD="update"; CATCHUP=1;;
		"list") CMD="list";;
		"delicious") CMD="delicious";;
		"-h") HELP=1;;
		"-d") DEBUG=1;;
		"-q") QUIET=1;;
	esac;
	shift;
done
test "$DEBUG" -gt 0 && echo "Command is $CMD" >&2;

# print help
if test "$HELP" -eq 1; then
	usage >&2
	exit 0
fi

# check / set up database
if test -e "$PODDB"; then
	FILEVER=`getdbver`;
	test "$DEBUG" -gt 0 && echo "Database $PODDB exists and is at version $FILEVER" >&2;
	if test "$FILEVER" -ne "$DBVER"; then
		echo "Database $PODDB is schema version $FILEVER but I only support $DBVER"
		exit 1;
	else
		test "$DEBUG" -gt 0 && echo "Database schema $DBVER supported by this code" >&2;
	fi
else
	test "$DEBUG" -gt 0 &&  echo "Creating database $PODDB" >&2;
	makepoddbV1;
fi

if test "$CMD" = "add"; then
	ID=`addpodcast $ADDURL`
	if test "$ID" -gt 0; then
		echo "Added $ADDURL at ID $ID";
	fi
	if test "$ID" -eq 0; then
		echo "$ADDURL is already added";
	fi
	if test "$ID" -lt 0; then
		echo "Error adding $ADDURL";
	fi

	exit 0;
fi
if test "$CMD" = "update"; then
	getpodcasts | while read i; do
		ID=`dbresultcol 1 "$i"`;
		URL=`dbresultcol 2 "$i"`;
		TITLE=`dbresultcol 3 "$i"`;
		checkpodcast "$ID" "$URL" "$TITLE";
	done
	exit 0;
fi
if test "$CMD" = "list"; then
	listcasts;
fi
if test "$CMD" = "delicious"; then
	delicious | while read line; do
		url=`dbresultcol 1 "$line"`;
		title=`dbresultcol 2 "$line"`;
		test "$DEBUG" -gt 0 && echo "Trying to add $url" >&2
		ID=`addpodcast $url`;
		if test "$ID" -gt 0; then
			echo "Added $title ($url) at ID $ID";
		fi
	done
	exit 0;
fi
