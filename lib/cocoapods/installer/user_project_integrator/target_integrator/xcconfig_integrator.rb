module Pod
  class Installer
    class UserProjectIntegrator
      class TargetIntegrator
        # Configures an user target to use the CocoaPods xcconfigs which allow
        # lo link against the Pods.
        #
        class XCConfigIntegrator
          # Integrates the user target.
          #
          # @param  [Target::AggregateTarget] pod_bundle
          #         The Pods bundle.
          #
          # @param  [Array<PBXNativeTarget>] targets
          #         The native targets associated which should be integrated
          #         with the Pod bundle.
          #
          def self.integrate(pod_bundle, targets)
            targets.each do |target|
              target.build_configurations.each do |config|
                update_to_cocoapods_0_34(pod_bundle, targets)
                set_target_xcconfig(pod_bundle, target, config)
              end
            end
          end

          private

          # @!group Integration steps
          #-------------------------------------------------------------------#

          # Removes the xcconfig used up to CocoaPods 0.33 from the project and
          # deletes the file if it exists.
          #
          # @param  [Target::AggregateTarget] pod_bundle
          #         The Pods bundle.
          #
          # @param  [Array<XcodeProj::PBXNativeTarget>] targets
          #         The native targets.
          #
          # @todo   This can be removed for CocoaPods 1.0
          #
          def self.update_to_cocoapods_0_34(pod_bundle, targets)
            sandbox = pod_bundle.sandbox
            targets.map(&:project).uniq.each do |project|
              file_refs = project.files.select do |file_ref|
                path = file_ref.path.to_s
                if File.extname(path) == '.xcconfig'
                  absolute_path = file_ref.real_path.to_s
                  absolute_path.start_with?(sandbox.root.to_s) &&
                    !absolute_path.start_with?(sandbox.target_support_files_root.to_s)
                end
              end

              file_refs.uniq.each do |file_ref|
                UI.message "- Removing (#{file_ref.path})" do
                  file_ref.remove_from_project
                end
              end
            end
          end

          # Creates a file reference to the xcconfig generated by
          # CocoaPods (if needed) and sets it as the base configuration of
          # build configuration of the user target.
          #
          # @param  [Target::AggregateTarget] pod_bundle
          #         The Pods bundle.
          #
          # @param  [PBXNativeTarget] target
          #         The native target.
          #
          # @param  [Xcodeproj::XCBuildConfiguration] config
          #         The build configuration.
          #
          def self.set_target_xcconfig(pod_bundle, target, config)
            path = pod_bundle.xcconfig_relative_path(config.name)
            group = config.project['Pods'] || config.project.new_group('Pods')
            file_ref = group.files.find { |f| f.path == path }
            existing = config.base_configuration_reference

            set_base_configuration_reference = ->() do
              file_ref ||= group.new_file(path)
              config.base_configuration_reference = file_ref
            end

            if existing && existing != file_ref
              if existing.real_path.to_path.start_with?(pod_bundle.sandbox.root.to_path << '/')
                set_base_configuration_reference.call
              elsif !xcconfig_includes_target_xcconfig?(config.base_configuration_reference, path)
                UI.warn 'CocoaPods did not set the base configuration of your ' \
                'project because your project already has a custom ' \
                'config set. In order for CocoaPods integration to work at ' \
                'all, please either set the base configurations of the target ' \
                "`#{target.name}` to `#{path}` or include the `#{path}` in your " \
                "build configuration (#{UI.path(existing.real_path)})."
              end
            elsif config.base_configuration_reference.nil? || file_ref.nil?
              set_base_configuration_reference.call
            end
          end

          private

          # @!group Private helpers
          #-------------------------------------------------------------------#

          # Prints a warning informing the user that a build configuration of
          # the integrated target is overriding the CocoaPods build settings.
          #
          # @param  [Target::AggregateTarget] pod_bundle
          #         The Pods bundle.
          #
          # @param  [XcodeProj::PBXNativeTarget] target
          #         The native target.
          #
          # @param  [Xcodeproj::XCBuildConfiguration] config
          #         The build configuration.
          #
          # @param  [String] key
          #         The key of the overridden build setting.
          #
          def self.print_override_warning(pod_bundle, target, config, key)
            actions = [
              'Use the `$(inherited)` flag, or',
              'Remove the build settings from the target.',
            ]
            message = "The `#{target.name} [#{config.name}]` " \
              "target overrides the `#{key}` build setting defined in " \
              "`#{pod_bundle.xcconfig_relative_path(config.name)}'. " \
              'This can lead to problems with the CocoaPods installation'
            UI.warn(message, actions)
          end

          # Naively checks to see if a given PBXFileReference imports a given
          # path.
          #
          # @param  [PBXFileReference] base_config_ref
          #         A file reference to an `.xcconfig` file.
          #
          # @param  [String] target_config_path
          #         The path to check for.
          #
          SILENCE_WARNINGS_STRING = '// @COCOAPODS_SILENCE_WARNINGS@ //'
          def self.xcconfig_includes_target_xcconfig?(base_config_ref, target_config_path)
            return unless base_config_ref && base_config_ref.real_path.file?
            regex = /
              ^(
                (\s*                                  # Possible, but unlikely, space before include statement
                  \#include\s+                        # Include statement
                  ['"]                                # Open quote
                  (.*\/)?                             # Possible prefix to path
                  #{Regexp.quote(target_config_path)} # The path should end in the target_config_path
                  ['"]                                # Close quote
                )
                |
                (#{Regexp.quote(SILENCE_WARNINGS_STRING)}) # Token to treat xcconfig as good and silence pod install warnings
              )
            /x
            base_config_ref.real_path.readlines.find { |line| line =~ regex }
          end
        end
      end
    end
  end
end
