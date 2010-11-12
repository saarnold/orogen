/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "<%= task.basename %>.hpp"

using namespace <%= task.component.name %>;

<%= task.basename %>::<%= task.basename %>(std::string const& name<%= ", TaskCore::TaskState initial_state" unless task.fixed_initial_state? %>)
    : <%= task.basename %>Base(name<%= ", initial_state" unless task.fixed_initial_state? %>)
{
}

<% task.self_operations.each do |op| %>
<%= op.signature { "#{task.basename}::#{op.method_name}" } %>
{
    <% if op.has_return_value? %>
    return <%= op.return_type.first.cxx_name %>();
    <% end %>
}
<% end %>

/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See <%= task.basename %>.hpp for more detailed
// documentation about them.

// bool <%= task.basename %>::configureHook()
// {
//     if (! <%= task.basename %>Base::configureHook())
//         return false;
//     return true;
// }
// bool <%= task.basename %>::startHook()
// {
//     if (! <%= task.basename %>Base::startHook())
//         return false;
//     return true;
// }
// void <%= task.basename %>::updateHook()
// {
//     <%= task.basename %>Base::updateHook();
// }
// void <%= task.basename %>::errorHook()
// {
//     <%= task.basename %>Base::errorHook();
// }
// void <%= task.basename %>::stopHook()
// {
//     <%= task.basename %>Base::stopHook();
// }
// void <%= task.basename %>::cleanupHook()
// {
//     <%= task.basename %>Base::cleanupHook();
// }

