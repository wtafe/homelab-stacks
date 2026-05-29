db = db.getSiblingDB("unifi");

db.createUser({
  user: "unifi",
  pwd: _getEnv("MONGO_PASS"),
  roles: [
    { role: "dbOwner", db: "unifi" },
    { role: "dbOwner", db: "unifi_stat" },
    { role: "dbOwner", db: "unifi_audit" },
    { role: "clusterMonitor", db: "admin" }
  ]
});