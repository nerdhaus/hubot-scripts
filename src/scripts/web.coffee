# Webutility
#
# returns title of urls

Select     = require("soupselect").select
HtmlParser = require "htmlparser"

class WebUrls
  constructor: (@robot) ->
    @cache = {
      urls: []
      users: []
    }
    @robot.brain.data.weburls = @cache

    @robot.brain.on 'loaded', =>
      if @robot.brain.data.weburls
        @cache = @robot.brain.data.weburls

  add: (url, title, user) ->
    if not @cache.users[user]
      @cache.users[user] = []
    @cache.urls[url] ?= title
    if @cache.urls.length > 10
      @cache.urls.shift
    @cache.users[user][url] ?= title
    if @cache.users[user].length > 10
      @cache.users[user].shift
    @robot.brain.data.weburls = @cache

  summary: ->
    s = []
    for key,val of @cache.urls
      s.unshift(key + " (" + val + ")")
    s.unshift("Recently mentioned URLs:")
    return s

  userSummary: (userName) ->
    s = []
    if @cache.users[userName]
      for key,val of @cache.users[userName]
        s.unshift(key + " (" + val + ")")
      s.unshift("URLs mentioned by " + userName + ":")
    else
      s.unshift(userName + " hasn't mentioned any URLs lately.")
    return s


module.exports = (robot) ->
  urls = new WebUrls robot

  robot.hear /(http|ftp|https):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&amp;:/~\+#]*[\w\-\@?^=%&amp;/~\+#])?/i, (msg) ->
    url = msg.match[0]
    sender   = msg.message.user.name.toLowerCase()
    httpResponse = (url) ->
      msg
        .http(url)
        .get() (err, res, body) ->
          if res.statusCode is 301 or res.statusCode is 302
            httpResponse(res.headers.location)
          else if res.statusCode is 200
            handler = new HtmlParser.DefaultHandler()
            parser  = new HtmlParser.Parser handler
            parser.parseComplete body
            results = (Select handler.dom, "head title")
            if results[0]
              title = results[0].children[0].data.replace(/(\r\n|\n|\r)/gm,"")
              msg.send title
              urls.add(url, title)
            else
              results = (Select handler.dom, "title")
              if results[0]
                title = results[0].children[0].data.replace(/(\r\n|\n|\r)/gm,"")
                msg.send title
                urls.add(url, title, sender)
          else
            msg.send "Error " + res.statusCode

    httpBitlyResponse = (url) ->
      msg
        .http("http://api.bitly.com/v3/info")
        .query
          login: process.env.HUBOT_BITLY_USERNAME
          apiKey: process.env.HUBOT_BITLY_API_KEY
          shortUrl: url
          format: "json"
        .get() (err, res, body) ->
          response = JSON.parse body
          responseTitle = response.data.info[0].title.replace(/(\r\n|\n|\r)/gm,"")
          if responseTitle
            msg.send if response.status_code is 200 then responseTitle else response.status_txt
          else
            httpResponse(url)

    if url.match /^http\:\/\/bit\.ly/
      httpBitlyResponse(url)
    else
      httpResponse(url)
  
  robot.respond /urls ?(\S+[^-\s])?$/i, (msg) ->
    if msg.match[1]
      s = urls.userSummary(msg.match[1])
    else
      s = urls.summary()

    for i of s
      msg.send s[i]
