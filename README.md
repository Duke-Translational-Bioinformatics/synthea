# Synthea Patient Generator [![Build Status](https://travis-ci.org/synthetichealth/synthea.svg?branch=master)](https://travis-ci.org/synthetichealth/synthea)

Synthea is a Synthetic Patient Population Simulator. The goal is to output synthetic, realistic (but not real), patient data and associated health records in a variety of formats.

Read our [wiki](https://github.com/synthetichealth/synthea/wiki) for more information.

Currently, Synthea features:
- Birth to Death Lifecycle
- Configuration-based statistics and demographics (defaults with Massachusetts Census data)
- Modular Rule System
  - Drop in [Generic Modules](https://github.com/synthetichealth/synthea/wiki/Generic-Module-Framework)
  - Custom Ruby rules modules for additional capabilities
- Primary Care Encounters, Emergency Room Encounters, and Symptom-Driven Encounters
- Conditions, Allergies, Medications, Vaccinations, Observations/Vitals, Labs, Procedures, CarePlans
- Formats
 - FHIR (STU3 v1.6)
 - C-CDA
- Rendering Rules and Disease Modules with Graphviz

## Quick Start

### Installation

**System Requirements:** 
Synthea requires Ruby 2.0.0 or above.

To clone the Synthea repo and install the necessary gems:
```
git clone https://github.com/synthetichealth/synthea.git
cd synthea
gem install bundler
bundle install
```

### Generate Synthetic Patients
Must have a running MongoDB instance (see https://docs.mongodb.com/getting-started/shell/introduction/)

Generating an entire population at once...

```
bundle exec rake synthea:generate
```
Or generating the population one at a time...

```
bundle exec rake synthea:sequential
```

Or generating the population for a county and time based on census statistics...

```
bundle exec rake synthea:sequential['./config/Suffolk_County.json']
```

Some settings can be changed in `./config/synthea.yml`.

Synthea will output patient records in C-CDA (requires running instance of Mongo DB) and FHIR STU3 formats in `./output`.

### Upload to FHIR Server
After generating data, upload it to a STU3 FHIR server:
```
bundle exec rake synthea:fhirupload[http://server/fhir/baseDstu3]
```

### Synthea GraphViz
Generate graphical visualizations of Synthea rules and modules. Requires GraphViz to be installed.

```
brew install graphviz
bundle exec rake synthea:graphviz
```

# License

Copyright 2016 The MITRE Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
