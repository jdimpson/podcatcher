#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import xml.sax
import requests
from datetime import datetime

def datesort(rss,reverse):
	if isinstance(rss,RssStreamParser):
		rss = list(rss.parseItems())
	rss.sort(key=lambda x: x['pubDate']['content'], reverse=reverse)
	return rss
def newest2oldest(rss):
	return datesort(rss, True)
def oldest2newest(rss):
	return datesort(rss, False)

def ct2type(ct):
	typ = None
	if "/atom+xml" in ct:
		typ = "atom"
	elif "/xml" in ct:
		typ = "rss"
	elif "/rss+xml" in ct:
		typ = "rss"
	elif "application/octet-stream" in ct:
		typ = "octets"
	else:
		typ = "unknown"
	return typ

# class from https://stackoverflow.com/questions/7693535/what-is-a-good-xml-stream-parser-for-python
class RssStreamSaxHandler(xml.sax.handler.ContentHandler):

	def __init__(self,contentcb=None):
		self.contentcb = contentcb
		self.tagstack = []
		self.attribdict = {}
		self.contentdict = {}

	def path(self):
		return '/' + '/'.join(self.tagstack)

	def startElement(self, name, attrs):
		self.tagstack.append(name)
		self.attribdict[self.path()] = attrs

	def endElement(self, name):
		path = self.path()
		if path in self.attribdict:
			a = self.attribdict[path].items()
			del self.attribdict[path]
		else:
			a = None

		if path in self.contentdict:
			c = self.contentdict[path]
			del self.contentdict[path]
		else:
			c = None

		#print("\n{}\n  attribs\t{}\n  content\t{}".format(path,str(a),c))
		
		self.tagstack.pop()
		if self.contentcb is not None:
			#print("cb")
			self.contentcb(path,c,a)

	def characters(self, content):
		if content is None or content == "" or content == " ":
			return
		content = content.encode('ascii','ignore')
		if self.path() in self.contentdict:
			self.contentdict[self.path()] += content
		else:
			self.contentdict[self.path()] = content
		#print("{} content={}".format(self.tagstack,content))

class RssStreamParser(object):
	def __init__(self,url, text=None, resp=None, type=None, verb=False, ua=None, timeout=None, raize=False, verify=True):
		self.verify = verify
		self.bail = False
		self.raize = raize
		self.verb = verb
		self.url = url
		self.parser = xml.sax.make_parser()
		self.parser.setContentHandler(RssStreamSaxHandler(contentcb=self.contentcb))
		self.elems = []
		if ua is not None:
		        hd = { 'User-Agent': ua, }
		else:
			hd = None
		self.type = None
		self.ct = None
		self.charset = 'utf-8'
		if text is not None:
			self.resp = None
			self.text = text
			self.type = type
		elif resp is not None:
			self.resp = resp
			self.text = ''
			self.check_resp()
		else:
			self.resp = requests.get(self.url,stream=True,headers=hd,timeout=timeout,verify=self.verify)
			self.text = ''
			self.check_resp()

	def check_resp(self):
		try:
			if self.verb: 
				print("Content-type of {url} is {ct}".format(ct=self.resp.headers['content-type'],url=self.url))
			self.ct = self.resp.headers['content-type']
		except KeyError as e:
			if self.verb: 
				print(e)
				print(self.resp.status_code)
				for h in self.resp.headers:
					print(h,self.resp.headers[h])
				print(self.resp.content)
			if self.resp.status_code == 404:
				self.ct = None
			else:
				raise e

		self.type = ct2type(self.ct)

		if self.type is None:
			self.bail = True

		if "charset=" in self.ct:
			self.charset = self.ct[self.ct.find("charset=") + len("charset="):]
			if self.verb: print("Found charset {}".format(self.charset))

		if self.type == "unknown" and self.verb:
			print("Got unknown content-type {}\n{}".format(self.ct, self.resp.text))

		if self.type == "octets":
			if self.charset.lower()  == 'utf-8': 
				self.type = 'rss'
				if self.verb: print("Blindly assuming octetstream type is RSS")
				

		if self.verb:
			print("character set is {}".format(self.charset))

	def contentcb(self,path,content,attributes):
		if isinstance(content,bytes):
			content = content.decode(self.charset)
		a = {}
		for t in attributes:
			k,v=t
			a[k]=v
		if path.endswith('pubDate'):
			fs = [
				'%a, %d %b %Y %H:%M:%S %Z', #Mon, 26 Apr 2021 21:26:03 GMT
				'%a, %d %b %Y %H:%M:%S %z', #Sun, 24 Nov 2019 17:21:51 -0500
			]
			for f in fs:
				try:
					content = datetime.strptime(content, f)
				except ValueError as e:
					pass
				else:
					break
		self.elems.append((path,content,a))

	def parse(self):
		if len(self.text) > 0:
			for i in self.feed(self.text):
				yield i
			return
		oldchunk = None
		for chunk in self.resp.iter_content(chunk_size=1024):
			#print("chunk")
			if chunk:
				if oldchunk is not None:
					chunk = oldchunk + chunk
					oldchunk = None
				try:
					chunk = chunk.decode(self.charset)
				except UnicodeDecodeError as e:
					if "unexpected end of data" in str(e):
						oldchunk = chunk
						continue
					if self.verb: print("bad chunk in hex\n{}".format(chunk.hex()))
					raise e
				self.text += chunk
				# NOTE: chunk was left as bytes for years, but recently the sax parser in feed() started choking on it if it had certain UTF characters (0xe28098 aka U+2018). 
				#       so now we are converting chunk to string before feeding it to the parser
				for i in self.feed(chunk):
					yield i

	def parseItems(self):
		if   self.isRss():
			return self.parseRssItems()
		elif self.isAtom():
			return self.parseAtomEntries()

	def isAtom(self):
		return self.type == "atom" 
	def isRss(self):
		return self.type == "rss"

	def parseAtomEntries(self):
		obj = {}
		for elem,content,attributes in self.parse():
			if elem == "/feed/entry":
				yield obj
				obj = {}
			elif elem.startswith("/feed/entry"):
				tag = elem[len("/feed/entry")+1:]
				if tag in obj:
					if obj[tag] is not None and content is not None:
						obj[tag] += content
				else:
					obj[tag] = content
	def parseRssItems(self):
		obj = {}
		for elem,content,attributes in self.parse():
			if elem == "/rss/channel/item":
				yield obj
				obj = {}
			elif elem.startswith("/rss/channel/item"):
				tag = elem[len("/rss/channel/item")+1:]
				if tag in obj:
					if obj[tag] is not None and content is not None:
						if not isinstance(obj[tag], list):
							tmp = obj[tag]
							obj[tag] = []
							obj[tag].append(tmp)
						obj[tag].append({'content':content, 'attributes':attributes})
				else:
					obj[tag] = {'content':content, 'attributes':attributes}

	def feed(self,chunk):
		try:
			self.parser.feed(chunk)
		except xml.sax._exceptions.SAXParseException as e:
			if self.raize:
				raise RssParseException(e)
			#raise RuntimeError("SAX parsing failed on {}".format(chunk))
			if self.verb: print("error {} in feed for {}, skipping".format(e, self.url))
			self.bail = True
		if self.bail: 
			return
		for i in self.elems:
			yield i
		#print("fed")
		self.elems = []

class RssParseException (Exception):
	pass


if __name__ == "__main__":
	from sys import argv
	bbc = 'http://feeds.bbci.co.uk/news/world/rss.xml'

	verb=True
	feed = None
	if len(argv) > 1:
		feed = argv[1]
	else:
		feed = bbc

	#fmt = "{pubDate[content]}\t{title[content]}\t{description[content]}"
	fmt = "{guid[content]}\t{pubDate[content]}\t{title[content]}\t{description[content]}"

	if verb:
		print(feed)
		print("Builtin requests")
	#for i in RssStreamParser(feed,verb=verb).parseItems():
	for i in oldest2newest(RssStreamParser(feed,verb=verb,ua="Me!",raize=True)):
		#print(i)
		#print(type(i['pubDate']['content']))
		if not "description" in i:
			if "itunes:summary" in i:
				i["description"] = i["itunes:summary"]
		print(fmt.format(**i))
	#print("External requests")
	#resp = requests.get(feed)
	#if resp.status_code != 200:
	#	print("error downloading {f}: {s}".format(f=feed,s=resp.status))
	#typ = ct2type(resp.headers['content-type'])
	#for i in RssStreamParser(None,text=resp.text,type=typ,verb=verb).parseItems():
	#	#print(i)
	#	if not "description" in i:
	#		if "itunes:summary" in i:
	#			i["description"] = i["itunes:summary"]
	#	print(fmt.format(**i))


