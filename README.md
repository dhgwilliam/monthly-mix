monthly-mix
===========

As of right now, the tool is not complete at all. I've been running it like this:

```
$ bundle exec ruby -Ilib lib/monthly-mix/lastfm.rb -u <username>
```

This will result in the tool collecting (and caching!) all your weekly charts forever and generating a list of "quarterly" mixes (13 weeks). There are a lot of weird things about this at the moment, as it compiles "quarterly" charts out of your weekly top 10, so it may not include all plays of a particular song over a particular time period.

Also, you need to get API key and secret from last.fm and store them in `LASTFM_KEY` and `LASTFM_SECRET` envvars. The first time you run it the script will output a URL that you must load in a browser and authorize the application. Once you have authorized, return to the terminal and hit enter. A session key will be stored in `~/.local/share/monthly-mix`, and you should not need to do this again.
