# satno2tle
Create TLE from SatNOGS observation as fast as possible. A collection of scripts

# requirements
you should have installed and worked:
[strf](https://github.com/cbassa/strf)
[satnogs-waterfall-tabulation-helper](https://github.com/hobisatelit/satnogs-waterfall-tabulation-helper)
[ikhnos](https://gitlab.com/kerel-fs/ikhnos/)

# auto.sh
this script will semi automatic create TLE from SatNOGS observation.
just put this auto.sh file inside directory of your satnogs-waterfall-tabulation-helper

# ichnos.sh
this script will running multiple ikhnos.py simultaneously as fast as possbile. this ikhnos will gets waterfall from a given observation and applies an overlay of the signal generated from given TLEs.
just put this ichnos.sh file inside directory of your ikhnos


