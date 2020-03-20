# nim_eloverblik
API for www.eloverblik.dk - samling af energiforbrug.

This is an API for the website www.eloverblik.dk, which collects energy usage from Danish energy companies.

You use this as an library, which you import, or you can run it as a binary. It'll get your energy usage, format it to JSON, and sends the data with MQTT.

# Requirements
To access the API, you need to generate a `refreshToken` and your meetering point.


## Refresh token
1) Go to www.eloverblik.dk
2) Login as "Privat"
3) Navigate to "Min profil -> Datadeling"
4) Generate a token and save it locally

## Meetering ID
You'r already at www.eloverblik.dk, so now just navigate to the frontpage (https://eloverblik.dk/Customer/overview/) and copy your meetering ID - the 18 characters.

# Data
Please be aware, that the data output comes within a time periode from 23:00-23:00 (11:00 PM): `"start":"2020-03-16T23:00:00Z","end":"2020-03-17T23:00:00Z"`.

Therefore the URL you are requesting look a bit strange. When you want the data from the 17th, you request needs to be from 16th to the 17th march.

Your URL will be: `https://api.eloverblik.dk/CustomerApi/api/MeterData/GetTimeSeries/2020-03-17/2020-03-18/Year`

Furthermore the datahub is updated 1 day to slow, which has the draw down, that you can't get yesterdays usage.


# Usage
You have to copy the `config_default.cfg` to `config.cfg` and adjust the options.


## Home Assistant (Hass.io)
The original purpose of this API was to enable an overview in HA. So running the API as a binary, it'll sends the stats everyday to HA, and you can visualize them - e.g. using mini-graph (HACS plugin).

Buuuut, you might want to use Node red to do the automation. You either follow the steps below to create the flow, or you can copy and paste the predefined flow. After that generate a graph with mini-graph in Lovelace and enjoy.

~~You need to let the program run, cause it'll gather the data once a day - set the time in the `config.cfg`. A good choice would be 23:30 - the data is updated around 23:00.~~ This was quite annoying while testing, so now the api just runs every half hour. If there's no changes, nothing is send to HA with MQTT.


### Node red

We are making 3 nodes for: Daily usage, Weekly usage, Monthly usage.

* MQTT-in node - convert to JSON object
* HA entity node (monthl) - set state to:
* HA entity node (week) - set state to:
* HA entity node (day) - set state to:

<details><summary>Node red JSON code</summary>

```json
[
    {
        "id": "5ea40d22.fd6134",
        "type": "mqtt in",
        "z": "f9f7e30c.acb0a",
        "name": "",
        "topic": "eloverblik",
        "qos": "2",
        "datatype": "json",
        "broker": "6e85e811.77a988",
        "x": 160,
        "y": 220,
        "wires": [
            [
                "875fd707.470408",
                "3f11ef06.a67ae",
                "37c6eb5c.e52be4"
            ]
        ]
    },
    {
        "id": "875fd707.470408",
        "type": "ha-entity",
        "z": "f9f7e30c.acb0a",
        "name": "Eloverblik Month",
        "server": "b95e3a52.453dc8",
        "version": 1,
        "debugenabled": true,
        "outputs": 1,
        "entityType": "sensor",
        "config": [
            {
                "property": "name",
                "value": "eloverblik_month"
            },
            {
                "property": "device_class",
                "value": ""
            },
            {
                "property": "icon",
                "value": ""
            },
            {
                "property": "unit_of_measurement",
                "value": ""
            }
        ],
        "state": "payload.eloverblik.month.0.usage",
        "stateType": "msg",
        "attributes": [
            {
                "property": "start",
                "value": "payload.eloverblik.month.0.start",
                "valueType": "msg"
            },
            {
                "property": "end",
                "value": "payload.eloverblik.month.0.end",
                "valueType": "msg"
            }
        ],
        "resend": true,
        "outputLocation": "",
        "outputLocationType": "none",
        "inputOverride": "allow",
        "x": 450,
        "y": 160,
        "wires": [
            []
        ]
    },
    {
        "id": "3f11ef06.a67ae",
        "type": "ha-entity",
        "z": "f9f7e30c.acb0a",
        "name": "Eloverblik Week",
        "server": "b95e3a52.453dc8",
        "version": 1,
        "debugenabled": true,
        "outputs": 1,
        "entityType": "sensor",
        "config": [
            {
                "property": "name",
                "value": "eloverblik_week"
            },
            {
                "property": "device_class",
                "value": ""
            },
            {
                "property": "icon",
                "value": ""
            },
            {
                "property": "unit_of_measurement",
                "value": ""
            }
        ],
        "state": "payload.eloverblik.week.0.usage",
        "stateType": "msg",
        "attributes": [
            {
                "property": "start",
                "value": "payload.eloverblik.week.0.start",
                "valueType": "msg"
            },
            {
                "property": "end",
                "value": "payload.eloverblik.week.0.end",
                "valueType": "msg"
            }
        ],
        "resend": true,
        "outputLocation": "",
        "outputLocationType": "none",
        "inputOverride": "allow",
        "x": 440,
        "y": 220,
        "wires": [
            []
        ]
    },
    {
        "id": "37c6eb5c.e52be4",
        "type": "ha-entity",
        "z": "f9f7e30c.acb0a",
        "name": "Eloverblik Day",
        "server": "b95e3a52.453dc8",
        "version": 1,
        "debugenabled": true,
        "outputs": 1,
        "entityType": "sensor",
        "config": [
            {
                "property": "name",
                "value": "eloverblik_day"
            },
            {
                "property": "device_class",
                "value": ""
            },
            {
                "property": "icon",
                "value": ""
            },
            {
                "property": "unit_of_measurement",
                "value": ""
            }
        ],
        "state": "payload.eloverblik.day.0.usage",
        "stateType": "msg",
        "attributes": [
            {
                "property": "start",
                "value": "payload.eloverblik.day.0.start",
                "valueType": "msg"
            },
            {
                "property": "end",
                "value": "payload.eloverblik.day.0.end",
                "valueType": "msg"
            }
        ],
        "resend": true,
        "outputLocation": "",
        "outputLocationType": "none",
        "inputOverride": "allow",
        "x": 440,
        "y": 280,
        "wires": [
            []
        ]
    },
    {
        "id": "6e85e811.77a988",
        "type": "mqtt-broker",
        "z": "",
        "name": "Main MQTT",
        "broker": "192.168.1.100",
        "port": "1883",
        "clientid": "noderedmqtt",
        "usetls": false,
        "compatmode": false,
        "keepalive": "60",
        "cleansession": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthPayload": "",
        "closeTopic": "",
        "closeQos": "0",
        "closePayload": "",
        "willTopic": "",
        "willQos": "0",
        "willPayload": ""
    },
    {
        "id": "b95a2a52.433dc8",
        "type": "server",
        "z": "",
        "name": "Home Assistant",
        "legacy": false,
        "addon": true,
        "rejectUnauthorizedCerts": true,
        "ha_boolean": "y|yes|true|on|home|open",
        "connectionDelay": true,
        "cacheJson": true
    }
]
```

</details>

### MQTT messages
The ouput will be like:
```json
{
   "eloverblik":{
     // Data from February 1st to February the 29
      "month":[
         {
            "start":"2020-01-31T23:00:00Z",
            "end":"2020-02-29T23:00:00Z",
            "usage":"114.62",
            "unit":"KWH"
         }
      ],
      // Data from Monday 9 to Sunday the 15
      "week":[
         {
            "start":"2020-03-08T23:00:00Z",
            "end":"2020-03-15T23:00:00Z",
            "usage":"44.55",
            "unit":"KWH"
         }
      ],
      // Data from Tuesday the 17th
      "day":[
         {
            "start":"2020-03-16T23:00:00Z",
            "end":"2020-03-17T23:00:00Z",
            "usage":"5.99",
            "unit":"KWH"
         }
      ]
   }
}
```


## Nim library

Import eloverblik, set the types and call `eloverblikTimeSeries()`:

```nim
eloverblikLoadData() # Loads the data from the config.cfg
let result = eloverblikTimeSeries(eloverblik, elperiode)
```

You do not need to fill out the MQTT in the `config.cfg` file.

### Options

The 2 data options in the config is `daysBack` and `daysSpecific`. For both these options you have to specify an aggregation.
For aggregation you can use `Actual | Quarter | Hour | Day | Month | Year`. If the aggregation is higher than the periode you are specifying, you'll get 1 result containing the whole usage.

You can use both of these options or have multiple dates in both of them - split the dates with a `;`.

I could look like:
```config
daysBack = "1;7;365"
aggregationBack = "Hour;Day;Month"

daysSpecific = "2020-01-01,2020-03-01" # 2020-01-01,2020-02-01;2020-02-01,2020-03-01
aggregationSpecific = "Month" # Month;Day
```

### Predefined calls

Do you prefer the data returned to Home Assistant? You can use the same predefined calls, which returns the last mont, week and day.

```nim
let url  = datesPredefined(mainPeriode, howLongBack, "Year")
# mainPeriode = Month, Week or Day
# howLongBack = How many months, weeks or days back, you want to see
```
```nim
# The Year in aggregation is used to ensure, that data from the periode is used

let monthUrl  = datesPredefined("Month", 1, "Year")
let month     = requestData(actualToken, "month", eloverblik.meeteringPoint, monthUrl)

let weekUrl   = datesPredefined("Week", 1, "Year")
let week      = requestData(actualToken, "week", eloverblik.meeteringPoint, weekUrl)

let dayUrl    = datesPredefined("Day", 1, "Year")
let day       = requestData(actualToken, "day", eloverblik.meeteringPoint, dayUrl)
```

# More
You can read more about the API the pdf `100120 Customer and Third party API for Datahub Eloverblik  Technical description.pdf`.