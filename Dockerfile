FROM alpine:latest AS run
RUN apk add --update python3 py3-pip py3-dateutil py3-eyed3 py3-mutagen py3-magic py3-requests py3-pillow
RUN mkdir -p /root/.podcatcher/ && touch /root/.podcatcher/podcatcher.sqlite && mkdir /podcasts
COPY basename.py /basename.py
COPY rssstream.py /rssstream.py
COPY podcatcher /podcatcher
RUN chmod a+x /podcatcher 
RUN /podcatcher -d setdir /podcasts
ENTRYPOINT ["/podcatcher"]
ARG ["help"]
