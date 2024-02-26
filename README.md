# podcatcher

## about
I'm some kind of anticapitalistic social pervert because I still download all my podcasts via RSS and save them to local storage. I used to use something called [hpodder](https://github.com/jgoerzen/hpodder), but it stopped being maintained. So I wrote a quick and dirty [shell script](historical-podcatcher.sh) using sqlite3, curl, and [xmlstarlet](https://xmlstar.sourceforge.net/). It worked, but was increasingly difficult to maintain. So as an excercise to learn python, I rewrote it. I've been using the python version for years (since December 2013), but only now (February 2024) decided to put it under version control.

The python version of [podcatcher](podcatcher) is very quirky, poorly written, and has even worse documentation. You shouldn't use it, if only because of my gall in naming the program after the generic noun.

Interesting feature of `podcatcher` is that it tries to preserve as much metadata about the podcast as it can. It stores lots of data in ID3 fields for MP3 and MP4 files. THIS PROGRAM CHANGES THE MEDIA FILES. Don't let that surprise you.

Hightlight of RSS feed metadata saved in ID3:

- The RSS description goes into a comment field; 
- Title, author, pbudate, etc. are saved in the appopriate ID3 fields;
- the original RSS feed URL goes into the "Audio source URL" field;
- the URL the podcast was downloaded from (prior to any HTTP redirects) goes into the Audio file URL field;
	- This is important to realize if you have any private RSS feeds like on Patreon or something. you might leak sensitive information; 
- Image files are added if missing (which might make your file much bigger);
	- If there is an episode-specific image, it is used, otherwise the podcast feed image is used.
- Regardless of whether an image file was added, the image URL gets added as an [indirect image](https://superuser.com/questions/1350654/when-embedding-cover-art-as-a-tag-to-audio-files-is-the-same-image-copied-to-ea/1351254#1351254);

It also changes the access time of the podcast file to equal that of the publication date it got from the RSS feed. This has the benefit that you can run `ls -t` in the podcast directory and see the files in publication order (newest to oldest). (I think there's a bug in the handling of timezones, by the way, if the RSS feed server doesn't use UTC. But there are always bugs when timezones are involved.)

(Someday I might publish my `find2rss.py` script that I use to republish a directory full of files as a new RSS feed--it relies on the file access time to create the pubdate field in the RSS field. It also uses the image URLs to create per-episode image links. Together these features are very convenient in making a podcast aggregator.)

BTW, no, this won't download anything from spotify. They are a walled garden, and are bad for podcasts. You shouldn't use them. Other than spotify, if you have trouble finding the RSS feed URL for your favorite podcast (because apple and google podcasts have disincentivised podcast creators from publishing the RSS URLs) you might have luck searching for them on [https://podcastaddict.com/](https://podcastaddict.com/). I actually find using the podcast addict app's built in search function even better, but that would require you to install the app on your phone or something.
## build and run
There's no automatic installation. YOu need to copy the files into your $PATH
```
git clone https://github.com/jdimpson/podcatcher/
cd podcatcher
cp podcatcher rssstream.py basename.py ~/bin
```
You also need the following third party python modules installed:
```
pip3 install python-dateutil
pip3 install eyed3
pip3 install mutagen
pip3 install python-magic
pip3 install requests
pip3 install pillow
```

First time running it, you need to say were you want the podcasts to get downloaded to:
```
podcatcher setdir ~/podcasts
```
THen you need to add some podcasts:
```
podcatcher add https://feeds.libsyn.com/444720/rss 
```
Subscriptions are stored in the file `$HOME/.podcatcher/podcatcher.sqlite`

You can list your subscribed podcasts like this:
```
podcatcher list
```
Note that the output includes the podcast number, which you can use as a shortcut in other commands.

Run the update command to check *every* podcast:
```
podcatcher update
```
Note that this will download **EVERY** new podcast in the feed. It might take a while. After a podcast is downloaded, it is marked as such in the file `$HOME/.podcatcher/podcatcher.sqlite`, and wont be downloaded again.

If you don't want to download every episode in a new podcast, you can catchup using the podcast number:
```
podcatcher catchupcast 1
```
This will mark every podcast as downloaded, without actually downloading them.  This is optional.

Then you want to arrange to run the podatcher every few hours, via crontab for example:
```
# min   hour			dayomon	month	weekday	command
25	0,3,6,9,12,15,18,21	*	*	*	$HOME/bin/podcatcher update
```

You can update just one podcast, if you make note of the podcast number in the list output:
```
podcatcher catchupcast 1
```

There are some other commands, but I don't use them enough to remember what they are. See `podcatcher help` for a hint about what else there is. Nothing major.

## container
I did end up containerizing `podcatcher`, in an effort to learn how to do that. Turns out running it in a container is useful in conjunction with some VPN client containers ([gluetun](https://github.com/qdm12/gluetun) or [my own](https://github.com/jdimpson/openvpn-client)) to get around the soft banning that google's feedburner service does when you accidentally download RSS feeds too fast. (Who knew that google was scared of a 300Mbps residential cable connection?) `podcatcher` now has an internal speed limit mechanism to try to avoid this. But it's not very smart: it only limits the request rate, not throughput. It's hard coded to one request per second, although it's easy to change in the code. Unfortunately google doesn't publish what an acceptable request or data rate is.

The one remaining problem with this containerization is that, if you are using `dockerd`, the podcasts which get downloaded into `podcasts/` directory are owned by the root user. All of the general solutions I've read for this are overcomplicated nonesense. Someday I may make it possible for the container to accept a user ID number passed via environmental variable, which would be used used in conjunction with `chown` to change the ownership of downloaded podcasts files. However, doing this would mean adding wrapper script around `podcatcher` and used as the entrypoint. I don't actually use the podcatcher in a container (yet) so I am not motivated (yet) to commit to an approach that I might not actually like. I hear that this problem doesn't happen with `podman`, which is on my list of things to learn about.

### build and run
```
git clone https://github.com/jdimpson/podcatcher/
docker build podcatcher/ -t jdimpson/podcatcher

touch podcatcher.sqlite
mkdir podcasts/

# set the source sqlite file and folder to whereever you want the database and downloaded podcasts t be.
DBMNT="type=bind,source=$(pwd)/podcatcher.sqlite,destination=/root/.podcatcher/podcatcher.sqlite";
PODMNT="type=bind,source=$(pwd)/podcasts,destination=/podcasts";
NET=

docker run -it --rm --mount "$DBMNT" --mount "$PODMNT" $NET jdimpson/podcatcher help
docker run -it --rm --mount "$DBMNT" --mount "$PODMNT" $NET jdimpson/podcatcher add https://feeds.libsyn.com/444720/rss 
docker run -it --rm --mount "$DBMNT" --mount "$PODMNT" $NET jdimpson/podcatcher list
docker run -it --rm --mount "$DBMNT" --mount "$PODMNT" $NET jdimpson/podcatcher update 
```

When in a container, you want to provide a volume/bind/mount/whatever location for the podcasts and another for the podcatcher.sqlite file. Otherwise, you won't have any state between invocations, and you won't be able to extract the downlaoded podcasts.

### other container settings
If you want to use a web proxy, then add this to the docker run command: `-e http_proxy=http://<proxyaddress>:<proxyport>/ -e https_proxy=http://<proxyaddress>:<proxyport>/` . 

I haven't tested `no_proxy` but it should work (as `podcatcher` just relies on python-requests default behaviors.)

If you want to use in conjunction with a containerized VPN client, such as [gluetun](https://github.com/qdm12/gluetun) or [jdimpson/openvpn-client](https://github.com/jdimpson/openvpn-client) (be sure to give them a name when you run them like `--name=vpngw`) then add to docker run: `--net=container:vpngw`

