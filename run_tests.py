#!/usr/bin/env python
import feedparser
import sys
import os

feed = feedparser.parse('./feed.rss')

absolute_address = "https://contravariance.rocks/"

def validate_path(path):
    replaced = path.replace(absolute_address, "")
    # If file doesn't exist or is empty, return false
    return os.path.getsize(replaced) != 0

def fail(message):
    print message
    sys.exit(1)

for entry in feed.entries:
    print "Validating", entry.title
    if not validate_path(entry["image"]["href"]):
        fail("Could not find image %s" % (entry["image"]))
    for enclosure in entry.enclosures:
        if int(enclosure["length"] == 0):
            fail("Invalid length for item '%s'" % (entry.title,))
        if not validate_path(enclosure["href"]):
            fail("Could not find mp3 '%s' for '%s'" % (enclosure["href"], entry.title,))
    (hours, minutes, _) = entry["itunes_duration"].split(":")
    if int(minutes) == 0 and int(hours) == 0:
        fail("Invalid duration parameter")
    if not validate_path(entry.link):
        fail("Missing document '%s'" % (entry.link,))
    if len(entry["summary_detail"]["value"]) == 0:
        fail("Missing summary for %s" % (entry.title,))
    if len(entry["content"]) == 0:
        fail("Missing content for %s" % (entry.title,))
print "Validation Successful"
