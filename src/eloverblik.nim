# Copyright 2020 - Thomas T. Jarløv

import httpClient, json, strutils, nmqtt, parsecfg, asyncdispatch, times
import nmqtt

type
  MqttInfo* = object
    host*: string
    port*: int
    username*: string
    password*: string
    topic*: string
    ssl*: bool
    clientname*: string

  Eloverblik* = object
    refreshToken*: string
    actualToken*: string
    meeteringPoint*: string
    refreshTime*: string
    runOnBoot*: bool

  Elperiode* = object
    daysBack*: string
    daysBackAggr*: string
    daysSpecific*: string
    daysSpecificAggr*: string

var
  mqttInfo*: MqttInfo
  eloverblik*: Eloverblik
  elperiode*: Elperiode



const
  urlBase = "https://api.eloverblik.dk/CustomerApi/"
  urlRefreshToken = "api/Token"
  urlTimeSeries = "api/MeterData/GetTimeSeries/$1/$2/$3"
  body = "{\"meteringPoints\": {\"meteringPoint\": [\"$1\"]} }"


proc eloverblikGetToken*(refreshToken: string): string =
  ## Gets the token

  var client = newHttpClient()

  client.headers = newHttpHeaders({ "Authorization": "Bearer " & refreshToken })

  let resp = parseJson((client.get(urlBase & urlRefreshToken)).body)

  return resp["result"].getStr()


proc sendMqtt(client: MqttInfo, data: string) {.async.} =
  ## Send data through mqtt

  let ctx = newMqttCtx(client.clientname)

  ctx.set_auth(client.username, client.password)
  ctx.set_host(client.host, client.port, client.ssl)
  ctx.set_ping_interval(60)

  await ctx.start()
  await sleepAsync(2000) # TODO removed
  await ctx.publish(client.topic, data, 2, true)
  await sleepAsync(2000) # TODO removed
  await ctx.close()


proc getMonth(m: string): Month =
  ## Return Month from month string. Could just use Datetime..
  case m
  of "01": return mJan
  of "02": return mFeb
  of "03": return mMar
  of "04": return mApr
  of "05": return mMay
  of "06": return mJun
  of "07": return mJul
  of "08": return mAug
  of "09": return mSep
  of "10": return mOct
  of "11": return mNov
  of "12": return mDec


proc formatResult(json: string): string =
  ## Formats eloverblik result.
  ##
  ## Returns:
  ##  {"start":"2020-01-31T23:00:00Z","end":"2020-02-01T23:00:00Z","usage":"4.47","unit":"KWH"}

  let j = parseJson(json)
  echo pretty(j)

  for a1 in j["result"]:

    for a2 in a1["MyEnergyData_MarketDocument"]["TimeSeries"]:
      let unit = a2["measurement_Unit.name"].getStr()

      for a3 in a2["Period"]:
        let startDate = a3["timeInterval"]["start"].getStr()
        let endDate = a3["timeInterval"]["end"].getStr()

        for a4 in a3["Point"]:
          let usage = a4["out_Quantity.quantity"].getStr()

          if result != "":
            result.add(",")

          result.add(("{\"start\":\"$1\",\"end\":\"$2\",\"usage\":\"$3\",\"unit\":\"$4\"}").format(startDate,endDate,usage,unit))

  return result


proc eloverblikTimeSeries*(elo: Eloverblik, elp: Elperiode): string = #JsonNode =
  ## Returns the raw output from start to end date with custom aggregation
  ##
  ## actualToken = The return from eloverblikGetToken()
  ## dates = YYYY-MM-DD,YYYY-MM-DD (startDate,endDate)
  ## aggreation = Actual | Quarter | Hour | Day | Month | Year
  ##
  ## You can pass multiple values separated by semicolon ;,
  ## to do multiple lookups. Just make sure dates and
  ## aggregation match:
  ##  dates = 2020-01-01,2020-02-01;2020-02-01,2020-03-01
  ##  aggreation = Day,Hour

  var client = newHttpClient()

  client.headers = newHttpHeaders({ "Authorization": "Bearer " & elo.actualToken, "Content-Type": "application/json" })

  var
    countName: int
    resp: string

  # When config for days back is used
  if elp.daysBack != "":
    var count: int
    let aggre = split(elp.daysBackAggr, ";")

    # Loop through all options splitted by ;
    for val in split(elp.daysBack, ";"):

      # Days back to epoch. Subtract 2 days api not allowing to use current date
      let
        daysbackepoch = toInt(epochTime()) - (parseInt(val)*86400) - 86400

      # Setting days in var, because it is changed when month is used for aggregation.
      var
        days = substr($(utc(fromUnix(daysbackepoch))), 0, 9)
        daycurr = substr($(utc(fromUnix(toInt(epochTime())-86400))), 0, 9)

      # If month is used for aggregation, the "daysback" is changed to first and
      # last date in the relevant months to avoid api-failure.
      if aggre[count] == "Month":
        var setMonth = $(parseInt(daycurr.substr(5,6)) - 1)
        if setMonth.len() == 1:
          setMonth = "0" & setMonth

        # Set current day with last months number to avoid getting half month
        daycurr = daycurr.substr(0,4) & setMonth & "-" & $getDaysInMonth(getMonth(setMonth), parseInt(daycurr.substr(0,3)))

        # Get months back
        if parseInt(val) <= 12:
          let
            monthsbackepoch = toInt(epochTime()) - (parseInt(val)*86400*30)
            monthsback = substr($(utc(fromUnix(monthsbackepoch))), 0, 9)
          var
            setMonth = $(parseInt(monthsback.substr(5,6)))
          if setMonth.len() == 1:
            setMonth = "0" & setMonth

          days = monthsback.substr(0,4) & setMonth & "-01"# & $getDaysInMonth(getMonth(setMonth), parseInt(monthsback.substr(0,3)))

      if resp != "":
        resp.add(",")
      echo urlBase & urlTimeSeries.format(days, daycurr, aggre[count])
      resp.add("\"" & $countName & "\": [" &
                formatResult(
                  client.postContent(
                    urlBase & urlTimeSeries.format(days, daycurr, aggre[count]),
                    body = body.format(elo.meeteringPoint)
                  )
                ) & "]"
              )

      count += 1
      countName += 1


  if elp.daysSpecific != "":
    var count: int
    let aggre = split(elp.daysSpecificAggr, ";")

    # Loop through specific dates. Don't check for validity.
    for val in split(elp.daysSpecific, ";"):
      let days = split(val, ",")

      if resp != "":
        resp.add(",")

      resp.add("\"" & $countName & "\": [" &
                formatResult(
                  client.postContent(
                    urlBase & urlTimeSeries.format(days[0], days[1], aggre[count]),
                    body = body.format(elo.meeteringPoint)
                  )
                ) & "]"
              )

      count += 1
      countName += 1

  return ("{\"eloverblik\":{" & resp & "}}")


proc nextDayEpoch(): int =
  ## Calculate epoch before run and
  ## returns the seconds.

  # An epoch week: 86400 seconds * 7 days
  let dayEpoch = 86400

  # Monday 2020-03-15 02:00 GMT 0
  var definedTime = 1584237600

  # Current epochtime
  let currEpoch = toInt(epochTime())

  # Loop until next monday are found
  while currEpoch > definedTime + dayEpoch:
    definedTime = definedTime + dayEpoch

  # Seconds until next monday
  return (definedTime + dayEpoch) - currEpoch


proc eloverblikGetData(): string =
  # Fetch data and send

  eloverblik.actualToken = eloverblikGetToken(eloverblik.refreshToken)

  return eloverblikTimeSeries(eloverblik, elperiode)


proc apiSetup() {.async.} =
  ## Run the async API

  let
    dict = loadConfig("config/config.cfg")

    host = dict.getSectionValue("MQTT","host")
    port = parseInt(dict.getSectionValue("MQTT","port"))
    username = dict.getSectionValue("MQTT","username")
    password = dict.getSectionValue("MQTT","password")
    topic = dict.getSectionValue("MQTT","topic")
    ssl = parseBool(dict.getSectionValue("MQTT","ssl"))
    clientname = dict.getSectionValue("MQTT","clientname")

    rtoken = dict.getSectionValue("Eloverblik","refreshToken")
    mpoint = dict.getSectionValue("Eloverblik","meeteringPoint")
    rtime = dict.getSectionValue("Eloverblik","refreshTime")
    runOnBoot = parseBool(dict.getSectionValue("Eloverblik","runOnBoot"))

    dback = dict.getSectionValue("Periode","daysBack")
    daggre = dict.getSectionValue("Periode","aggregationBack")
    sback = dict.getSectionValue("Periode","daysSpecific")
    saggre = dict.getSectionValue("Periode","aggregationSpecific")

  mqttInfo.host = host
  mqttInfo.port = port
  mqttInfo.username = username
  mqttInfo.password = password
  mqttInfo.topic = topic
  mqttInfo.ssl = ssl
  mqttInfo.clientname = clientname

  eloverblik.refreshToken = rtoken
  eloverblik.meeteringPoint = mpoint
  eloverblik.refreshTime = rtime
  eloverblik.runOnBoot = runOnBoot

  elperiode.daysBack = dback
  elperiode.daysBackAggr = daggre
  elperiode.daysSpecific = sback
  elperiode.daysSpecificAggr = saggre

  let ctx = newMqttCtx(mqttInfo.clientname)
  ctx.set_auth(mqttInfo.username, mqttInfo.password)
  ctx.set_host(mqttInfo.host, mqttInfo.port, mqttInfo.ssl)
  ctx.set_ping_interval(60)
  await ctx.start()

  if eloverblik.runOnBoot:
    let data = eloverblikGetData()
    #await ctx.publish(mqttInfo.topic, data, 2, true)

  while true:
    await sleepAsync(nextDayEpoch() * 1000)
    let data = eloverblikGetData()
    #await ctx.publish(mqttInfo.topic, data, 2, true)

  await ctx.close()

when isMainModule:
  waitFor apiSetup()