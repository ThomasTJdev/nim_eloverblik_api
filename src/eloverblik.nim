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


proc eloverblikLoadData*(configPath = "config/config.cfg") =
  ## Loads the data

  let
    dict = loadConfig(configPath)

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

proc getDaysAfterMonday(d: MonthdayRange, m: Month, y: string): int =
  ## Return the days since last monday

  let weekDay = getDayOfWeek(d, m, parseInt(y))

  case weekDay
  of dMon: return 0
  of dTue: return 1
  of dWed: return 2
  of dThu: return 3
  of dFri: return 4
  of dSat: return 5
  of dSun: return 6


proc formatResult(json: string): string =
  ## Formats eloverblik result.
  ##
  ## Returns:
  ##  {"start":"2020-01-31T23:00:00Z","end":"2020-02-01T23:00:00Z","usage":"4.47","unit":"KWH"}

  let j = parseJson(json)

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


proc datesPredefined(choice: string, backCount: int, aggreation: string): string =
  ## Return predefined choices

  const monthSeconds = 86400 * 24 * 30

  let
    cDateEpoch    = toInt(epochTime())
    cDate         = substr($(utc(fromUnix(cDateEpoch))), 0, 9) # YYYY-MM-DD
    cDateTime     = utc(fromUnix(cDateEpoch))
    cYear         = substr(cDate, 0, 3)
    cMonthNr      = substr(cDate, 5, 6)
    cMonth        = getMonth(cMonthNr)
    cDay          = substr(cDate, 8, 9)
    cDaysInMonth  = $getDaysInMonth(getMonth(cMonthNr), parseInt(cDate.substr(0,3)))

  var
    toDate: string
    fromDate: string

  case choice

  of "Month":

    #[
      To
    ]#
    var
      sMonthNrTmp     = parseInt(cMonthNr)
      sYear           = cYear

    # If this is Januar, month will be 0 - go back to last year
    if sMonthNrTmp <= 0:
      sMonthNrTmp = 12
      sYear       = $(parseInt(sYear) - 1)

    if sMonthNrTmp >= 12:
      sMonthNrTmp = sMonthNrTmp - 12
      sYear       = $(parseInt(sYear) + 1)

    let
      sMonthNr        = if ($sMonthNrTmp).len() == 1: "0" & $sMonthNrTmp else: $sMonthNrTmp
      sMonth          = getMonth(sMonthNr)
      sDaysInMonth    = $(getDaysInMonth(sMonth, parseInt(sYear)))

    # Ready to set start date
    toDate = sYear & "-" & sMonthNr & "-" & "01"

    #[
      From
    ]#
    let
      eDateTime     = if backCount == 1: cDateTime else: cDateTime - (backCount - 1).months
      eDate         = substr($(eDateTime), 0, 9) # YYYY-MM-DD

    var
      eMonthNr      = substr(eDate, 5, 6)
      eMonthNrTmp   = parseInt(eMonthNr) - 1
      eYear         = parseInt(substr(eDate, 0, 3))
      #eYear         = eYear

    # If this is Januar, month will be 0 - go back to last year
    if eMonthNrTmp <= 0:
      eMonthNrTmp = 12
      eYear       = eYear - 1

    eMonthNr        = if ($eMonthNrTmp).len() == 1: "0" & $eMonthNrTmp else: $eMonthNrTmp
    let
      eMonth          = getMonth(eMonthNr)
      eDaysInMonth    = $getDaysInMonth(eMonth, eYear)

    if backCount == 1:
      fromDate = $eYear & "-" & eMonthNr & "-" & "01" #eDaysInMonth
    else:
      fromDate = $eYear & "-" & eMonthNr & "-" & "01" #eDaysInMonth

  of "Week":

    let
      subtractDay     = getDaysAfterMonday(parseInt(cDay), cMonth, cYear)
      sDateTime       = cDateTime - subtractDay.days
      eDateTime       = cDateTime - subtractDay.days - backCount.weeks

    toDate       = substr($(sDateTime), 0, 9) # YYYY-MM-DD
    fromDate         = substr($(eDateTime), 0, 9) # YYYY-MM-DD


  of "Day":
    let
      sDateTime       = cDateTime
      eDateTime       = cDateTime - backCount.days

    toDate       = substr($(sDateTime), 0, 9) # YYYY-MM-DD
    fromDate         = substr($(eDateTime), 0, 9) # YYYY-MM-DD


  let url = urlBase & urlTimeSeries.format(fromDate, toDate, aggreation)
  when defined(dev):
    echo url

  return url


proc datesCalc(elp: Elperiode, count: int, val: string, aggre: seq[string]): tuple[startDate: string, endDate: string] =
  ## Calc the dates based on user input

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

  return (days, daycurr)


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

  let actualToken = eloverblikGetToken(elo.refreshToken)

  client.headers = newHttpHeaders({ "Authorization": "Bearer " & actualToken, "Content-Type": "application/json" })

  var
    countName: int
    resp: string

  # When config for days back is used
  if elp.daysBack != "":
    var count: int
    let aggre = split(elp.daysBackAggr, ";")

    # Loop through all options splitted by ;
    for val in split(elp.daysBack, ";"):

      let (days, daycurr) = datesCalc(elp, count, val, aggre)

      if resp != "":
        resp.add(",")

      when defined(dev):
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

      when defined(dev):
        echo urlBase & urlTimeSeries.format(days[0], days[1], aggre[count])

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


proc requestData(actualToken, name, meeteringPoint, url: string): string =

  var client = newHttpClient()

  client.headers = newHttpHeaders({ "Authorization": "Bearer " & actualToken, "Content-Type": "application/json" })

  return ("\"" & name & "\": [" &
            formatResult(client.postContent(url, body = body.format(meeteringPoint))) & "]"
          )


proc apiRun(ctx: MqttCtx, mqttInfo: MqttInfo, elo: Eloverblik) {.async.} =
  ## Run the api

  let actualToken = eloverblikGetToken(eloverblik.refreshToken)

  #let data = eloverblikGetData()

  let monthUrl  = datesPredefined("Month", 1, "Year")
  let month     = requestData(actualToken, "month", elo.meeteringPoint, monthUrl)

  let weekUrl   = datesPredefined("Week", 1, "Year")
  let week      = requestData(actualToken, "week", elo.meeteringPoint, weekUrl)

  let dayUrl    = datesPredefined("Day", 1, "Year")
  let day       = requestData(actualToken, "day", elo.meeteringPoint, dayUrl)

  let json      = ("{\"eloverblik\":{" & month & ", " & week & ", " & day & "}}")

  await ctx.publish(mqttInfo.topic, json, 2, true)


proc apiSetup() {.async.} =
  ## Run the async API
  #[
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
  ]#
  eloverblikLoadData()

  let ctx = newMqttCtx(mqttInfo.clientname)
  ctx.set_auth(mqttInfo.username, mqttInfo.password)
  ctx.set_host(mqttInfo.host, mqttInfo.port, mqttInfo.ssl)
  ctx.set_ping_interval(60)
  await ctx.start()
  if eloverblik.runOnBoot:
    await apiRun(ctx, mqttInfo, eloverblik)

  while true:
    await sleepAsync(nextDayEpoch() * 1000)
    await apiRun(ctx, mqttInfo, eloverblik)

  await ctx.close()

when isMainModule:
  waitFor apiSetup()