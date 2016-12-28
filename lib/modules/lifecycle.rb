module Synthea
  module Modules
    class Lifecycle < Synthea::Rules
      attr_accessor :male_growth, :male_weight, :female_growth, :female_weight
      attr_accessor :races, :ethnicity, :blood_types

      def initialize
        super
        @male_growth = Synthea::Utils::Distribution.normal(Synthea::Config.lifecycle.growth_rate_male_average, Synthea::Config.lifecycle.growth_rate_male_stddev)
        @male_weight = Synthea::Utils::Distribution.normal(Synthea::Config.lifecycle.weight_gain_male_average, Synthea::Config.lifecycle.weight_gain_male_stddev)
        @female_growth = Synthea::Utils::Distribution.normal(Synthea::Config.lifecycle.growth_rate_female_average, Synthea::Config.lifecycle.growth_rate_female_stddev)
        @female_weight = Synthea::Utils::Distribution.normal(Synthea::Config.lifecycle.weight_gain_female_average, Synthea::Config.lifecycle.weight_gain_female_stddev)
      end

      # People are born
      rule :birth, [], [:age] do |time, entity|
        unless entity.had_event?(:birth)
          entity[:age] = 0
          entity[:name_first] = Faker::Name.first_name
          entity[:name_last] = Faker::Name.last_name
          if Synthea::Config.population.append_hash_to_person_names == true
            entity[:name_first] = "#{entity[:name_first]}#{(entity[:name_first].hash % 999)}"
            entity[:name_last] = "#{entity[:name_last]}#{(entity[:name_last].hash % 999)}"
          end
          entity[:gender] ||= gender
          entity[:race] ||= Synthea::World::Demographics::RACES.pick
          entity[:ethnicity] ||= Synthea::World::Demographics::ETHNICITY[entity[:race]].pick
          entity[:blood_type] = Synthea::World::Demographics::BLOOD_TYPES[entity[:race]].pick
          entity[:sexual_orientation] = Synthea::World::Demographics::SEXUAL_ORIENTATION.pick.to_s
          entity[:fingerprint] = Synthea::Fingerprint.generate if Synthea::Config.population.generate_fingerprints
          # new babies are average weight and length for American newborns
          entity.set_vital_sign(:height, 51.0, 'cm')
          entity.set_vital_sign(:weight, 3.5, 'kg')
          entity[:multiple_birth] = rand(3) + 1 if rand < Synthea::Config.lifecycle.prevalence_of_twins
          entity.events.create(time, :birth, :birth, true)
          entity.events.create(time, :encounter, :birth)
          entity.events.create(time, :symptoms_cause_encounter, :birth)

          # determine lat/long coordinates of address within MA
          location_data = Synthea::Location.select_point(entity[:city])
          entity[:coordinates_address] = location_data['point']
          zip_code = Synthea::Location.get_zipcode(location_data['city'])
          entity[:address] = {
            'line' => [Faker::Address.street_address],
            'city' => location_data['city'],
            'state' => 'MA',
            'postalCode' => zip_code
          }
          entity[:address]['line'] << Faker::Address.secondary_address if rand < 0.5
          entity[:city] = location_data['city']

          # telephone
          entity[:telephone] = Faker::PhoneNumber.phone_number

          # birthplace
          entity[:birth_place] = {
            'city' => Synthea::Location.select_point['city'],
            'state' => 'MA'
          }

          # parents
          mothers_name = Faker::Name.first_name
          mothers_name = "#{mothers_name}#{(mothers_name.hash % 999)}" if Synthea::Config.population.append_hash_to_person_names == true

          mothers_surname = Faker::Name.last_name
          mothers_surname = "#{mothers_surname}#{(mothers_surname.hash % 999)}" if Synthea::Config.population.append_hash_to_person_names == true
          entity[:name_mother] = "#{mothers_name} #{mothers_surname}"

          fathers_name = Faker::Name.first_name
          fathers_name = "#{fathers_name}#{(fathers_name.hash % 999)}" if Synthea::Config.population.append_hash_to_person_names == true
          entity[:name_father] = "#{fathers_name} #{entity[:name_last]}"

          # identifiers
          entity[:identifier_ssn] = "999-#{rand(10..99)}-#{rand(1000..9999)}"

          entity[:med_changes] = Hash.new { |hsh, key| hsh[key] = [] }
          choose_socioeconomic_values(entity)
        end
      end

      # People age
      rule :age, [:birth, :age], [:age] do |time, entity|
        if entity.alive?(time)
          birthdate = entity.event(:birth).time
          age = entity[:age]
          entity[:age] = ((time.to_i - birthdate.to_i) / 1.year).floor
          if entity[:age] > age
            dt = nil
            begin
              dt = DateTime.new(time.year, birthdate.month, birthdate.mday, birthdate.hour, birthdate.min, birthdate.sec, birthdate.formatted_offset)
            rescue StandardError
              # this person was born on a leap-day
              dt = time
            end
            entity.events.create(dt.to_time, :grow, :age)
          end
          # stuff happens when you're an adult
          if entity[:age] == 16
            # you get a driver's license
            entity[:identifier_drivers] = "S999#{rand(10_000..99_999)}" unless entity[:identifier_drivers]
          elsif entity[:age] == 18
            # you get respect
            if entity[:gender] == 'M'
              entity[:name_prefix] = 'Mr.' unless entity[:name_prefix]
            else
              entity[:name_prefix] = 'Ms.' unless entity[:name_prefix]
            end
          elsif entity[:age] == 20 && entity[:identifier_passport].nil?
            # you might get a passport
            entity[:identifier_passport] = (rand(0..1) == 1)
            entity[:identifier_passport] = "X#{rand(10_000_000..99_999_999)}X" if entity[:identifier_passport]
          elsif entity[:age] == 27 && !entity[:marital_status] # median age of marriage (26 for women, 28 for men)
            if rand < 0.8
              # you might get married
              entity[:marital_status] = 'M'
              if entity[:gender] == 'F'
                entity[:name_prefix] = 'Mrs.'
                entity[:name_maiden] = entity[:name_last]
                entity[:name_last] = Faker::Name.last_name
                entity[:name_last] = "#{entity[:name_last]}#{(entity[:name_last].hash % 999)}"
              end
            else
              entity[:marital_status] = 'S'
            end
            # this doesn't account for divorces or widows right now
          elsif entity[:age] == 30
            # you might get overeducated
            entity[:name_suffix] = %w(PhD JD MD).sample if entity[:ses] && entity[:ses][:education] >= 0.95 && !entity[:name_suffix]
          end
        end
      end

      # People grow
      rule :grow, [:age, :gender], [:height, :weight, :bmi] do |time, entity|
        # Assume a linear growth rate until average size is achieved at age 20
        # TODO consider genetics, social determinants of health, etc
        if entity.alive?(time)
          unprocessed_events = entity.events.unprocessed.select { |e| e.type == :grow }
          unprocessed_events.each do |event|
            entity.events.process(event)
            age = entity[:age]
            gender = entity[:gender]
            height = entity.get_vital_sign_value(:height)
            weight = entity.get_vital_sign_value(:weight)
            if age <= 20
              if gender == 'M'
                height += @male_growth.call # centimeters
                weight += @male_weight.call # kilograms
              elsif gender == 'F'
                height += @female_growth.call # centimeters
                weight += @female_weight.call # kilograms
              end
            elsif age <= Synthea::Config.lifecycle.adult_max_weight_age
              # getting older and fatter
              range = Synthea::Config.lifecycle.adult_weight_gain
              adult_weight_gain = rand(range.first..range.last)
              weight += adult_weight_gain
            elsif age >= Synthea::Config.lifecycle.geriatric_weight_loss_age
              # getting older and wasting away
              range = Synthea::Config.lifecycle.geriatric_weight_loss
              geriatric_weight_loss = rand(range.first..range.last)
              weight -= geriatric_weight_loss
            end
            # set the BMI
            entity.set_vital_sign(:height, height, 'cm')
            entity.set_vital_sign(:weight, weight, 'kg')
            entity.set_vital_sign(:bmi, calculate_bmi(height, weight), 'kg/m2')
          end
        end
      end

      # People die
      rule :death, [:age], [] do |time, entity|
        if entity.alive?(time)
          if rand <= likelihood_of_death(entity[:age])
            entity.events.create(time, :death, :death, true)
            self.class.record_death(entity, time)
          end
        end
      end

      def gender(ratios = { male: 0.5 })
        value = rand
        if value < ratios[:male]
          'M'
        else
          'F'
        end
      end

      # height in centimeters
      # weight in kilograms
      def calculate_bmi(height, weight)
        (weight / ((height / 100) * (height / 100)))
      end

      def likelihood_of_death(age)
        # http://www.cdc.gov/nchs/nvss/mortality/gmwk23r.htm: 820.4/100000
        x = if age < 1
              # 508.1/100000/365
              508.1 / 100_000
            elsif age >= 1  && age <= 4
              # 15.6/100000/365
              15.6 / 100_000
            elsif age >= 5  && age <= 14
              # 10.6/100000/365
              10.6 / 100_000
            elsif age >= 15 && age <= 24
              # 56.4/100000/365
              56.4 / 100_000
            elsif age >= 25 && age <= 34
              # 74.7/100000/365
              74.7 / 100_000
            elsif age >= 35 && age <= 44
              # 145.7/100000/365
              145.7 / 100_000
            elsif age >= 45 && age <= 54
              # 326.5/100000/365
              326.5 / 100_000
            elsif age >= 55 && age <= 64
              # 737.8/100000/365
              737.8 / 100_000
            elsif age >= 65 && age <= 74
              # 1817.0/100000/365
              1817.0 / 100_000
            elsif age >= 75 && age <= 84
              # 4877.3/100000/365
              4877.3 / 100_000
            elsif age >= 85 && age <= 94
              # 13499.4/100000/365
              13_499.4 / 100_000
            else
              # 50000/100000/365
              50_000.to_f / 100_000
            end
        Synthea::Rules.convert_risk_to_timestep(x, 365)
      end

      def self.age(time, birthdate, deathdate, unit = :years)
        case unit
        when :months
          left = deathdate.nil? ? time : deathdate
          (left.month - birthdate.month) + (12 * (left.year - birthdate.year)) + (left.day < birthdate.day ? -1 : 0)
        else
          divisor = 1.method(unit).call

          left = deathdate.nil? ? time : deathdate
          ((left - birthdate) / divisor).floor
        end
      end

      def self.socioeconomic_score(entity)
        weighting = Synthea::Config.socioeconomic_status.weighting

        ses = entity[:ses]

        (ses[:education] * weighting.education) + (ses[:income] * weighting.income) + (ses[:occupation] * weighting.occupation)
      end

      def self.socioeconomic_category(entity)
        categories = Synthea::Config.socioeconomic_status.categories

        score = socioeconomic_score(entity)

        case score
        when categories.low[0]...categories.low[1]
          return 'Low'
        when categories.middle[0]...categories.middle[1]
          return 'Middle'
        when categories.high[0]..categories.high[1]
          return 'High'
        else
          raise "socioeconomic score #{score} outside expected range, make sure weightings add to 1 and categories cover 0..1"
        end
      end

      def choose_socioeconomic_values(entity)
        # for now, these are assigned at birth
        # eventually these should be able to change. for example major illness before age 18 could lead to a reduced education
        entity[:ses] = {}

        if entity[:income]
          # simple linear formula just maps federal poverty level to 0.0 and 75,000 to 1.0
          # 75,000 chosen based on https://www.princeton.edu/~deaton/downloads/deaton_kahneman_high_income_improves_evaluation_August2010.pdf

          # (11000, 0) -> (75000, 1)
          # m = y2-y1/x2-x1 = 1/64000
          # y = mx+b, y = x/64000 - 11/64
          entity[:ses][:income] = if entity[:income] >= 75_000
                                    1.0
                                  elsif entity[:income] <= 11_000
                                    0.0
                                  else
                                    entity[:income].to_f / 64_000 - 11.0 / 64.0
                                  end
        else
          entity[:ses][:income] = rand
        end

        edu_scores = Synthea::Config.socioeconomic_status.values.education

        if entity[:education].nil?
          entity[:ses][:education] = rand
        else
          range = edu_scores.send(entity[:education])
          entity[:ses][:education] = rand(range[0]..range[1])
        end

        entity[:ses][:occupation] = rand # by default occupation is only 10% of SES and is tough to quantify, so just make it random
      end

      # This returns a random integer in a supplied range, possibly weighted; weighting ranges from 0 (prefer
      # lower numbers) to 5 (even distribution) to 10 (prefer higher numbers)
      def self.weighted_random_distribution(range, weighting)
        # NOTE: Could probably be updated to use Distribution::Exponential.rng in some way
        raise 'Error, weighting must range from 0 to 10' if weighting < 0 || weighting > 10
        # Normalize the range to have a min of 0
        normalized_max = range.max - range.min
        # Generate a curve based either on a root or a power for the appropriate shape
        exponent = (15.0 - weighting) / 10.0 # Ranges from 5/10 to 15/10
        # Start with a random number in the normalized range, apply the curve exponent, and normalize again to the original range
        value = (rand * normalized_max)**exponent
        normalization_factor = normalized_max / (normalized_max**exponent)
        (range.min + (value * normalization_factor)).round
      end

      #------------------------------------------------------------------------# begin class record functions
      def self.record_death(entity, time, reason = nil)
        entity.record_synthea.death(time)
        if reason
          entity[:cause_of_death] = reason
          # TODO: once CCDA supports cause of death, change the ccda_method parameter
          entity.record_synthea.encounter(:death_certification, time)
          entity.record_synthea.observation(:cause_of_death, time, reason, :observation, :no_action)
          entity.record_synthea.diagnostic_report(:death_certificate, time, 1) # note: ccda already no action here
        end
      end
    end
  end
end
