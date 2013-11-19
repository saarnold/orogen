module OroGen
    module Loaders
        # Definition of the base loader API
        class Base
            # Set of projects loaded so far
            #
            # @return [Hash<String,Spec::Project>]
            attr_reader :loaded_projects

            # Set of task models that are known to us
            attr_reader :loaded_task_models

            # The registry that includes types from all loaded typekits
            attr_reader :registry

            # The list of types that can be used on an oroGen interface
            attr_reader :interface_typelist

            # A mapping from type names to the typekits that define them
            attr_reader :typekits_by_type_name

            # Set of typekits loaded so far
            #
            # @return [Hash<String,Spec::Typekit>]
            attr_reader :loaded_typekits

            # The loader that should be used to resolve dependencies
            attr_reader :root_loader

            # Set of typekits that should be loaded on every project
            #
            # @return [Set<Spec::Typekit>]
            attr_reader :default_typekits

            # Sets the behaviour of the type resolution on unknown types
            #
            # @return [Boolean]
            attr_predicate :define_dummy_types?, true

            # Set of callbacks that are called whenever a new typekit gets
            # loaded
            #
            # @return [Array<#call>]
            attr_reader :typekit_load_callbacks

            # Set of callbacks that are called whenever a new typekit gets
            # loaded
            #
            # @return [Array<#call>]
            attr_reader :project_load_callbacks

            def initialize(root_loader = self)
                @loaded_projects = Hash.new
                @loaded_typekits = Hash.new
                @loaded_task_models = Hash.new
                @root_loader = root_loader
                @default_typekits = Set.new
                @typekits_by_type_name = Hash.new
                @registry = Typelib::Registry.new
                @interface_typelist = Set.new
                @typekit_load_callbacks = Array.new
                @project_load_callbacks = Array.new
            end

            # Returns the project model corresponding to the given name
            #
            # @param [String] the project name
            # @raise [OroGen::NotFound] if there is no project with that
            #   name.
            # @return [OroGen::Spec::Project]
            def project_model_from_name(name)
                if project = loaded_projects[name]
                    return project
                end

                name = name.to_str

                text, path = project_model_text_from_name(name)

                OroGen.info "loading oroGen project #{name}"
                project = Spec::Project.new(root_loader)
                project.typekit =
                    if has_typekit?(name)
                        typekit_model_from_name(name)
                    else
                        Spec::Typekit.new(root_loader, name)
                    end

                Loaders::Project.new(project).__eval__(path, text)
                register_project_model(project)
                project
            end
            
            # Registers a callback that should be called with newly registered
            # projects
            #
            # @param [Boolean] initial_events if true, the callbacks will be
            #   called instantly with the projects that have already been loaded
            def on_project_load(initial_events = true, &block)
                project_load_callbacks << block
                if initial_events
                    current_set = loaded_projects.values.dup
                    current_set.each do |p|
                        block.call(p)
                    end
                end
            end

            # Returns the task library model corresponding to the given name
            # @param (see project_model_from_name)
            # @raise [OroGen::NotFound] if there is no task library with that
            #   name. This does including having a project with that name if the
            #   project defines no tasks.
            # @return (see project_model_from_name)
            def task_library_model_from_name(name)
                project = project_model_from_name(name)
                if project.self_tasks.empty?
                    raise OroGen::NotFound, "there is an oroGen project called #{name}, but it defines no tasks"
                end
                project
            end

            # Returns the task model object corresponding to a model name
            #
            # @param [String] name the task model name
            # @return [Spec::TaskContext]
            # @raise [OroGen::NotFound] if there are no such model
            def task_model_from_name(name)
                if model = loaded_task_models[name]
                    return model
                end

                tasklib_name = find_task_library_from_task_model_name(name)
                if !tasklib_name
                    raise OroGen::NotFound, "no task model #{name} is registered"
                end

                tasklib = project_model_from_name(tasklib_name)
                result = tasklib.tasks[name]
                if !result
                    raise InternalError, "while looking up model of #{name}: found project #{tasklib_name}, but this project does not actually have a task model called #{name}"
                end

                result
            end

            # Returns the deployment model for the given deployment name
            #
            # @param [String] name the deployment name
            # @return [OroGen::Spec::Deployment] the deployment model
            # @raise [OroGen::NotFound] if no deployment with that name exists
            def deployment_model_from_name(name)
                project_name = find_project_from_deployment_name(name)
                if !project_name
                    raise OroGen::NotFound, "there is no deployment called #{name}"
                end

                project = project_model_from_name(project_name)
                deployment = project.deployers[name]
                if !deployment
                    raise InternalError, "cannot find the deployment called #{name} in #{project.name}. Candidates were #{project.deployers.map(&:name).sort.join(", ")}"
                end
                deployment
            end

            # Returns the deployed task model for the given name
            #
            # @param [String] name the deployed task name
            # @param [String] deployment_name () the name of the deployment in which the
            #   task is defined. It must be given only when more than one deployment
            #   defines a task with the requested name
            # @return [OroGen::Spec::TaskDeployment] the deployed task model
            # @raise [OroGen::NotFound] if no deployed tasks with that name exists
            # @raise [OroGen::NotFound] if deployment_name was given, but the requested
            #   task is not defined in this deployment
            # @raise [OroGen::AmbiguousName] if more than one task exists with that
            #   name. In that case, you will have to provide the deployment name
            #   explicitly using the second argument
            def deployed_task_model_from_name(name, deployment_name = nil)
                if deployment_name
                    deployment = deployment_model_from_name(deployment_name)
                else
                    deployment_names = find_deployments_from_deployed_task_name(name)
                    if deployment_names.empty?
                        raise OroGen::NotFound, "cannot find a deployed task called #{name}"
                    elsif deployment_names.size > 1
                        raise OroGen::AmbiguousName, "more than one deployment defines a deployed task called #{name}: #{deployment_names.map(&:name).sort.join(", ")}"
                    end
                    deployment = deployment_model_from_name(deployment_names.first)
                end

                if !(task = deployment.find_task_by_name(name))
                    if deployment_name
                        raise OroGen::NotFound, "deployment #{deployment_name} does not have a task called #{name}"
                    else
                        raise InternalError, "deployment #{deployment_name} was supposed to have a task called #{name} but does not"
                    end
                end
                task
            end

            # Loads a typekit from its name
            #
            # @param [String] name the typekit name
            # @return [Spec::Typekit] the typekit
            # @raise [OroGen::NotFound] if the typekit cannot be found
            def typekit_model_from_name(name)
                if typekit = loaded_typekits[name]
                    return typekit
                end

                registry_xml, typelist_txt = typekit_model_text_from_name(name)
                typekit = Spec::Typekit.from_raw_data(root_loader, name, registry_xml, typelist_txt)
                register_typekit_model(typekit)
                typekit
            end

            # Registers information from this typekit
            #
            # Callbacks registered by {#on_typekit_load} gets called with the
            # new typekit as argument
            def register_typekit_model(typekit)
                registry.merge typekit.registry
                @interface_typelist |= typekit.interface_typelist
                typekit.typelist.each do |typename|
                    typekits_by_type_name[typename] ||= Set.new
                    typekits_by_type_name[typename] << typekit
                end
                loaded_typekits[typekit.name] = typekit
                typekit_load_callbacks.each do |callback|
                    callback.call(typekit)
                end
            end

            def register_type_model(type, interface = true)
                registry.merge type.registry.minimal(type.name)
                if interface
                    interface_typelist << type.name
                end
            end
            
            # Registers a callback that should be called with newly registered
            # typekits
            #
            # @param [Boolean] initial_events if true, the callbacks will be
            #   called instantly with the typekits that have already been loaded
            def on_typekit_load(initial_events = true, &block)
                typekit_load_callbacks << block
                if initial_events
                    current_set = loaded_typekits.values.dup
                    current_set.each do |tk|
                        block.call(tk)
                    end
                end
            end

            # Resolves a type object
            #
            # @param [#name,String] type the type to be resolved
            # @return [Model<Typelib::Type>] the corresponding type in
            #   {#registry}
            # @raise Typelib::NotFound if the type cannot be found
            def resolve_type(type)
                type = type.name if type.respond_to?(:name)
                registry.get(type)
            rescue Typelib::NotFound
                if define_dummy_types?
                    type = registry.create_null(typename)
                    interface_typelist << typename
                    return type
                else raise
                end
            end

            # Returns the typekit object that defines this type
            def imported_typekits_for(typename)
		if typename.respond_to?(:name)
		    typename = typename.name
		end
                if typekits = typekits_by_type_name[typename]
                    typekits
                else raise ArgumentError, "#{typename} is not an imported type"
                end
            end

            # Returns the type object for +typename+, validating that we can use
            # it in a task interface, i.e. that it will be registered in the
            # RTT's typeinfo system
            def resolve_interface_type(typename)
                type = resolve_type(typename)
                if type < Typelib::ArrayType
                    raise InvalidInterfaceType.new(type), "static arrays are not valid interface types. Use an array in a structure or a std::vector"
                elsif !interface_type?(type)
                    typekits = imported_typekits_for(type.name)
                    raise NotExportedType.new(type, typekits), "#{type.name}, defined in the #{typekits.map(&:name).join(", ")} typekits, is never exported"
                end
                type
            end

            # Tests whether the given type can be used on an interface
            #
            # @param [#name,String] typename the type
            # @return [Boolean]
            def interface_type?(typename)
                typename = typename.name if typename.respond_to?(:name)
                interface_typelist.include?(typename)
            end

            # Returns the opaque type that is paired with the given type
            #
            # @param [#name,String] type the type to be resolved
            # @return [Model<Typelib::Type>]
            def opaque_type_for(type)
                imported_typekits_for(type).first.opaque_type_for(type)
            end

            # Returns the intermediate type that is paired with the given type
            #
            # @param [#name,String] type the type to be resolved
            # @return [Model<Typelib::Type>]
            def intermediate_type_for(type)
                imported_typekits_for(type).first.intermediate_type_for(type)
            end

            # Returns whether this type is a m-type (intermediate type generated
            # by oroGen)
            def m_type?(type)
                imported_typekits_for(type).first.m_type?(type)
            end

            # Registers this project's subobjects
            def register_project_model(project)
                loaded_task_models.merge! project.tasks
                loaded_projects[project.name] = project
                project_load_callbacks.each do |callback|
                    callback.call(project)
                end
            end

            # Returns the textual representation of a project model
            #
            # @param [String] the project name
            # @raise [OroGen::NotFound] if there is no project with that
            #   name.
            # @return [(String,String)] the model as text, as well as a path to
            #   the model file (or nil if there is no such file)
            def project_model_text_from_name(name)
                raise NotImplementedError
            end

            # Returns the textual representation of a typekit
            #
            # @param [String] the typekit name
            # @raise [OroGen::NotFound] if there is no typekit with that name
            # @return [(String,String)] the typekit registry as XML and the
            #   typekit's typelist
            def typekit_model_text_from_name(name)
                raise NotImplementedError
            end

            # Tests if a project with that name exists
            #
            # @param [String] name the project name
            # @return [Boolean]
            def has_project?(name)
                raise NotImplementedError
            end

            # Tests if a typekit with that name exists
            #
            # @param [String] name the typekit name
            # @return [Boolean]
            def has_typekit?(name)
                raise NotImplementedError
            end

            # Returns the task library name in which a task model is defined
            #
            # @param [String] model_name the name of the task model to look for
            # @return [String,nil]
            def find_task_library_from_task_model_name(name)
                raise NotImplementedError
            end

            # Returns the project that defines the given deployment
            #
            # @param [String] deployment_name the deployment we are looking for
            # @return [String,nil]
            def find_project_from_deployment_name(name)
                raise NotImplementedError
            end

            # Returns the set of deployments that contain a certain task
            #
            # @param [String] name
            # @return [Set<String>]
            def find_deployments_from_deployed_task_name(name)
                raise NotImplementedError
            end
        end
    end
end