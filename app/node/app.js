const express = require("express");
const pool = require("./db");
const app = express();
const GeoJSON = require("geojson");
const cors = require("cors");
const bodyParser = require("body-parser");
// use it before all route definitions
app.use(cors({ origin: "*" }));
app.use(function(request, response, next) {
  response.header("Access-Control-Allow-Origin", "*");
  response.header(
    "Access-Control-Allow-Methods",
    "POST, GET, PUT, DELETE, OPTIONS"
  );
  response.header("Access-Control-Allow-Credentials", "false");
  response.header("Access-Control-Max-Age", "86400"); // 24 hours
  if (request.method == "OPTIONS") {
    response.status(204).end();
  } else {
    next();
  }
});

var jsonParser = bodyParser.json();
// to support JSON-encoded bodies
var urlencodedParser = bodyParser.urlencoded({ extended: false });


app.post("/api/userdata", jsonParser, (request, response) => {
  //CRUD OPERATION
  var mode = request.body.mode;
  function returnResult(err, res) {
    if (err) return console.log(err);
    response.send(res.rows);
  }
  if (mode == "read") {
    //read is used to fill tha array of ways delete features ids on the application startup
    pool.query(
      "SELECT * FROM user_data where id = ($1)",
      [request.body.user_id],
      returnResult
    );
  } else if (mode == "update") {
    //update is used to fill the array with ways features that are not drawned by the user
    pool.query(
      "UPDATE user_data SET deleted_feature_ids=($2) WHERE id=($1)",
      [request.body.user_id, request.body.deleted_feature_ids],
      returnResult
    );
  } else if (mode == "delete") {
    //delete is used to delete the feature from ways_modified table if the user has drawned that feature by himself
    pool.query(
      "DELETE FROM ways_modified WHERE id=($1)",
      [request.body.drawned_fid],
      returnResult
    );
    //*later we can require guid (unique id) for security here, for the user to be able to delete the feature and use a nodejs library to prevent sql incjection attacks*//
  } else if (mode == "insert") {
    pool.query(
      "INSERT INTO user_data (id) VALUES ($1)",
      [request.body.id],
      returnResult
    );
  }
});

app.get("/api/isochrone", jsonParser, (request, response) => {
  let requiredParams = [
    "user_id",
    "minutes",
    "x",
    "y",
    "n",
    "speed",
    "concavity",
    "modus"
  ];
  let queryValues = [];

  requiredParams.forEach(key => {
    let value = request.query[key];
    if (!value) {
      response.send("An error happened");
      return;
    }
    queryValues.push(value);
  });

  console.log(queryValues);
  // Make sure to set the correct content type
  response.set("content-type", "application/json");

  pool.query(
    `SELECT jsonb_build_object(
		'type',     'FeatureCollection',
		'features', jsonb_agg(features.feature)
	)
	FROM (
	SELECT jsonb_build_object(
		'type',       'Feature',
		'id',         gid,
		'geometry',   ST_AsGeoJSON(geom)::jsonb,
		'properties', to_jsonb(inputs) - 'gid' - 'geom'
	) AS feature 
	FROM (SELECT * FROM isochrones_api($1,$2,$3,$4,$5,$6,$7,$8)) inputs) features;`,
    queryValues,
    (err, res) => {
      if (err) return console.log(err);
      console.log(res);
      response.send(res.rows[0].jsonb_build_object);
    }
  );
});


module.exports = app;
