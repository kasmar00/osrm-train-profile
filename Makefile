.PRECIOUS: world/%-latest.osm.pbf

# List all the source countries we need
WANTED_COUNTRIES := $(shell grep -v "\#" countries.wanted)

# Helper: replace / with _
flatten = $(subst /,_,$(1))
unflatten = $(subst _,/,$(1))

# Transform "germany/bayern" -> "world/germany_bayern-latest.osm.pbf"
COUNTRIES_PBF := $(foreach c,$(WANTED_COUNTRIES),world/$(call flatten,$(c))-latest.osm.pbf)

# Download the raw source file of a country
world/%-latest.osm.pbf:
	wget -N -nv -O $@ https://download.geofabrik.de/europe/$(call unflatten,$*)-latest.osm.pbf

# Filter a raw country (in world/*) to rail-only data (in filtered/*)
filtered/%-latest.osm.pbf: world/%-latest.osm.pbf filter.params
	osmium tags-filter --expressions=filter.params $< -o $@ --overwrite

# Combine all rail-only data (in filtered/*) into one file
output/filtered.osm.pbf: $(subst world,filtered,$(COUNTRIES_PBF))
	osmium merge $^ -o $@ --overwrite

# Compute the real OSRM data on the combined file
output/filtered.osrm.edges: output/filtered.osm.pbf basic.lua
	docker run --rm -t -v $(shell pwd):/opt/host ghcr.io/project-osrm/osrm-backend osrm-extract -p /opt/host/basic.lua /opt/host/$<
	docker run --rm -t -v $(shell pwd):/opt/host ghcr.io/project-osrm/osrm-backend osrm-partition /opt/host/$<
	docker run --rm -t -v $(shell pwd):/opt/host ghcr.io/project-osrm/osrm-backend osrm-customize /opt/host/$<

all: output/filtered.osrm.edges

serve: output/filtered.osrm.edges basic.lua
	docker run --rm -t -i -p 5000:5000 -v $(shell pwd):/opt/host ghcr.io/project-osrm/osrm-backend osrm-routed --algorithm mld /opt/host/output/filtered.osrm

clean:
	rm -f output/filtered.osrm.*
	rm -f output/filtered.osm.pbf
	rm -f filtered/*.pbf

dist-clean: clean
	rm -f world/*.pbf
