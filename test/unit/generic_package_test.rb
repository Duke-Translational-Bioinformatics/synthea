require_relative '../test_helper'

class GenericPackageTest < Minitest::Test

  def setup
    @time = Time.now
    @patient = Synthea::Person.new
    @patient[:gender] = 'F'
    @patient.events.create(@time - 35.years, :birth, :birth)
    @patient[:age] = 35
  end

  def test_new_package
    # Load the package and test that it loaded correctly.
    package = get_package('test_package')
    assert_equal("test_package", package.name)
    assert_equal(1, package.submodules.length)

    # Test the the package has the correct main context
    # to start execution from.
    main = package.main
    assert_equal("Test Package Main Module", main['name'])
    assert_equal("test_package", main['package'])
    assert_equal(5, main['states'].keys.length)

    # Test that the package's submodule loaded correctly.
    submodule = package.submodules["Test Package Submodule"]
    assert_equal("Test Package Submodule", submodule['name'])
    assert_equal("test_package", submodule['package'])
    assert_equal(4, submodule['states'].keys.length)
  end

  def test_run_package
    package = get_package('test_package')
    main = Synthea::Generic::Context.new(package.main)

    # The main context should first block at the CallSubmodule.
    blocking_state = main.run(@time, @patient)
    assert_equal("CallSubmodule", blocking_state.name)
    assert_equal("Test Package Submodule", blocking_state.submodule)
    expected_args = {
      "condition" => "Examplitis",
      "encounter" => "Encounter"
    }
    assert_equal(expected_args, blocking_state.args)

    # Running the submodule that's called should block at it's Wellness state.
    submodule = Synthea::Generic::Context.new(package.submodules["Test Package Submodule"])
    submodule.history = main.history
    submodule.args = blocking_state.args
    blocking_state = submodule.run(@time, @patient)
    assert_equal("Wellness", blocking_state.name)

    # Resuming the main should then block at it's terminal state.
    blocking_state = main.run(@time, @patient)
    assert_equal("Main_Terminal", blocking_state.name)

    # Verify that the patient's record was updated correctly.
    encounters = @patient.record_synthea.encounters
    assert_equal(1, encounters.length)

    conditions = @patient.record_synthea.conditions
    assert_equal(1, conditions.length)
    assert_equal(:acute_examplitis, conditions[0]['type'])

    # Verify that the patient's MedicationOrder used the submodule's
    # args correctly.
    medications = @patient.record_synthea.medications
    assert_equal(1, medications.length)
    assert_equal(@time, medications[0]['start_time'])
    assert_equal(:acute_examplitis, medications[0]['reasons'][0])
  end

  def get_package(package_path)
    Synthea::Generic::Package.new(get_path(package_path))
  end

  def get_path(file_or_dir)
    fixture_dir = File.expand_path('../../fixtures/generic', __FILE__)
    File.join(fixture_dir, file_or_dir)
  end

end
