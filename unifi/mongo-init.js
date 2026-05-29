db = db.getSiblingDB("unifi");

db.createUser({
  user: "unifi",
  pwd: process.env.MONGO_PASS,
  roles: [
    { role: "dbOwner", db: "unifi" },
    { role: "dbOwner", db: "unifi_stat" }
  ]
});