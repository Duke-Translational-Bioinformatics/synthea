require_relative '../test_helper'

class GenericContextTest < Minitest::Test

  def setup
    @time = Time.now
    @patient = Synthea::Person.new
    @patient[:gender] = 'F'
    @patient.events.create(@time - 35.years, :birth, :birth)
    @patient[:age] = 35
  end

  def test_runner_from_module
    context = get_context('encounter.json')
    runner = Synthea::Generic::ContextRunner.new(context)
    assert_equal("Encounter", runner.name)
    assert_equal(0, runner.history.length)
    assert_equal(nil, runner.package)
    assert_equal(1, runner.stack.length)
    assert_equal(context, runner.active_context)

    runner.run(@time, @patient)

    # Check the history
    history = runner.active_context.history
    assert_equal(1, history.length)
    assert_equal("Initial", history[0].name)

    # Perform a wellness encounter
    @time += 1.year
    st = runner.active_context.current_state
    st.perform_encounter(@time, @patient, false)
    runner.run(@time, @patient)

    # Check the history after the wellness encounter
    history = runner.active_context.history
    assert_equal(2, history.length)
    assert_equal("Annual_Physical", history[1].name)

    # Perform 6-month Delay
    @time += 6.months
    runner.run(@time, @patient)
    history = runner.active_context.history
    assert_equal(4, history.length)
    assert_equal("Diabetes", history[3].name)
  end

  def test_runner_from_package
    package = get_package('test_package')
    runner = Synthea::Generic::ContextRunner.new(package)
    assert_equal("test_package", runner.name)
    assert_equal(0, runner.history.length)
    assert_equal(1, runner.package.submodules.length)
    assert_equal(1, runner.stack.length)
    assert_equal(package.main, runner.active_context)

    # Eventually the runner will block at a wellness encounter in the submodule.
    runner.run(@time, @patient)
    assert_equal(2, runner.stack.length)
    history = runner.active_context.history
    assert_equal(6, history.length)
    assert_equal("MedicationOrder", history.last.name)
    # The wellness state hasn't been processed yet
    assert_equal("Wellness", runner.active_context.current_state.name)

    # process the wellness encounter and resume execution
    @time += 1.year
    st = runner.active_context.current_state
    st.perform_encounter(@time, @patient, false)
    runner.run(@time, @patient)

    # The module should have finished executing and the stack should be empty
    assert_equal(0, runner.stack.length)
    assert_equal(nil, runner.active_context)
    # The runner should have the final version of the module's history
    history = runner.history
    assert_equal("Main_Terminal", history.last.name)

    # Test that the medication recorded in the patient's record has
    # the correct references to states in the parent module using the
    # args passed to it.
    enc = @patient.record_synthea.encounters.last
    med = @patient.record_synthea.medications.last
    assert_equal(enc['time'], med['time'])
    assert_equal(:acute_examplitis, med['reasons'][0])

    runner.log_history
  end

  def test_recursive_calls_to_submodules
    # Tests nested calls to submodules.
    package = get_package('test_package_recursive')
    runner = Synthea::Generic::ContextRunner.new(package)
    assert_equal("test_package_recursive", runner.name)

    # Should block in the encounter submodule, before the encounter
    runner.run(@time, @patient)
    assert_equal(2, runner.stack.length)
    assert_equal("Delay", runner.active_context.current_state.name)
    history = runner.active_context.history
    assert_equal("Initial", history.last.name)

    # check that the args were passed correctly
    ctx = runner.active_context
    expected = {
      "condition" => "Example_Condition"
    }
    assert_equal(expected, ctx.args)

    # Should block in the sub-submodule, after the MedicationOrder
    @time += 1.years
    runner.run(@time, @patient)
    assert_equal(3, runner.stack.length)
    assert_equal("Delay_Yet_Again", runner.active_context.current_state.name)
    history = runner.active_context.history
    assert_equal("Examplitis_Medication", history.last.name)

    # check that the args were passed correctly
    ctx = runner.active_context
    expected = {
      "condition" => "Example_Condition",
      "encounter" => "Encounter_In_Submodule"
    }
    assert_equal(expected, ctx.args)

    # Should run back to the encounter submodule and block before its terminal state
    @time += 3.weeks
    runner.run(@time, @patient)
    assert_equal(2, runner.stack.length)
    assert_equal("Delay_Some_More", runner.active_context.current_state.name)
    history = runner.active_context.history
    # Calls to submodules get logged in the history twice: once when they're called
    # and once after they return. This bookends the submodule's states nicely when
    # looking at a log.
    assert_equal("Med_Terminal", history.last.name)

    # Should run to completion after this last Delay, ending the condition
    # and the medication.
    @time += 5.weeks
    runner.run(@time, @patient)
    assert_equal(0, runner.stack.length)
    assert_equal(nil, runner.active_context)
    history = runner.history
    assert_equal("Terminal", history.last.name)

    runner.log_history

    # Check that the patient's record was updated correctly and that the args
    # were used correctly.
    cond = @patient.record_synthea.conditions.last
    assert_equal(:examplitis, cond['type'])
    assert_equal(@time, cond['end_time'])

    enc = @patient.record_synthea.encounters.last
    assert_equal(:examplitis, enc['reason'])

    med = @patient.record_synthea.medications.last
    assert_equal(:examplitis, med['reasons'][0])
    assert_equal(@time, med['stop'])

    # All should have started concurrently
    assert_equal(cond['time'], enc['time'])
    assert_equal(enc['time'], med['time'])
  end

  def test_logging
    # Can't really test the quality of the logs, but at least ensure it logs when it should and that nothing crashes
    old_log_value = Synthea::Config.generic.log

    # First check it doesn't log when it shouldn't
    Synthea::Config.generic.log = false
    package = get_package('test_package')
    runner = Synthea::Generic::ContextRunner.new(package)
    runner.run(@time, @patient)
    @time += 1.year
    st = runner.active_context.current_state
    st.perform_encounter(@time, @patient, false)
    runner.run(@time, @patient)
    assert_equal("Main_Terminal", runner.history.last.name)
    refute(runner.logged)

    # Then check it does log when it should
    Synthea::Config.generic.log = true
    package = get_package('test_package')
    runner = Synthea::Generic::ContextRunner.new(package)
    runner.run(@time, @patient)
    @time += 1.year
    st = runner.active_context.current_state
    st.perform_encounter(@time, @patient, false)
    runner.run(@time, @patient)
    assert_equal("Main_Terminal", runner.history.last.name)
    assert(runner.logged)

    # Set the log value back
    Synthea::Config.generic.log = old_log_value
  end

  def get_package(package_name)
    Synthea::Generic::Package.new(get_path(package_name))
  end

  def get_context(file_name)
    Synthea::Generic::Context.new(get_config(file_name))
  end

  def get_config(file_name)
    JSON.parse(File.read(get_path(file_name)))
  end

  def get_path(file_name)
    File.join(File.expand_path("../../fixtures/generic", __FILE__), file_name)
  end

  def create_state(typ, name)
    Object.const_get("Synthea::Generic::States::#{typ}").new(self, name)
  end
end
