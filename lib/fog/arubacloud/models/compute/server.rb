#
# Author:: Alessio Rocchi (<alessio.rocchi@staff.aruba.it>)
# © Copyright ArubaCloud.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
#

require 'fog/compute/models/server'
require 'fog/arubacloud/error'

module Fog
  module Compute
    class ArubaCloud
      class Server < Fog::Compute::Server
        CREATING = 1
        STOPPED = 2
        RUNNING = 3
        ARCHIVED = 4
        DELETED = 5

        # This is the instance ID which is unique per Datacenter
        identity :id, :aliases => 'ServerId'

        attribute :name, :aliases => 'Name'
        attribute :state, :aliases => 'ServerStatus'
        attribute :memory, :aliases => 'RAMQuantity', :squash => 'Quantity'
        attribute :cpu, :aliases => 'CPUQuantity', :squash => 'Quantity'
        attribute :hypervisor, :aliases => 'HypervisorType'
        attribute :datacenter_id, :aliases => 'DatacenterId'
        attribute :hd_qty, :aliases => 'HDQuantity'
        attribute :hd_total_size, :aliases => 'HDTotalSize'
        attribute :smart_ipv4, :aliases => 'EasyCloudIPAddress', :squash => 'Value'
        attribute :smart_package, :aliases => 'EasyCloudPackageID'
        attribute :vnc_port, :aliases => 'VncPort'
        attribute :admin_passwd
        attribute :vm_type
        attribute :ipv4_addr
        attribute :package_id
        attribute :template_id, :aliases => 'OSTemplateId'
        attribute :template_description, :aliases => 'OSTemplate', :squash => :Description

        ignore_attributes :CompanyId, :Parameters, :VirtualDVDs, :RenewDateSmart, :Note, :CreationDate,
                          :ControlToolActivationDate, :ControlToolInstalled, :UserId, :ScheduledOperations, :Snapshots,
                          :ActiveJobs

        def initialize(attributes = {})
          @service = attributes[:service]

          if attributes[:vm_type].nil?
            self.vm_type = 'smart' if attributes['HypervisorType'].eql? '4' || 'pro'
          end

          super
        end

        # Is server in ready state
        # @param [String] ready_state By default state is RUNNING
        # @return [Boolean] return true if server is in ready state
        def ready?(ready_state=RUNNING)
          state == ready_state
        end

        # Is server in stopped state
        # @param [String] stopped_state By default stopped state is STOPPED
        # @return [Boolean] return true if server is in stopped state
        def stopped?(stopped_state=STOPPED)
          state == stopped_state
        end

        # Is server in creating state
        # @param [String] creating_state By default creating state is CREATING
        # @return [Boolean] return true if server is in creating state
        def creating?(creating_state=CREATING)
          state == creating_state
        end

        def save
          if persisted?
            update
          else
            create
          end
        end

        def create
          requires :name, :cpu, :memory, :admin_passwd, :vm_type
          data = attributes

          if vm_type.eql? 'pro'
            # Automatically purchase a public ip address
            data[:ipv4_id] = service.purchase_ip['Value']['ResourceId']
            service.create_vm_pro(data)
          elsif vm_type.eql? 'smart'
            service.create_vm_smart(data)
          else
            raise Fog::ArubaCloud::Errors::BadParameters.new('VM Type can be smart or pro.')
          end

          # Retrieve new server list and filter the current virtual machine
          # in order to retrieve the ID
          # In case of failure, I will try it 3 for 3 times
          try = 0
          while server.is? nil && try <= 3
            server = service.get_servers.fetch('Value').select {|v| v.values_at('Name').include?(data[:name])}.first
            Fog::Logger.debug("Fog::Compute::ArubaCloud::Server.create, server: #{server.inspect}")
            if server
              merge_attributes(server)
            else
              message = "error during attribute merge, `server` object is not ready, try n.#{try}"
              Fog::Logger.warning("Fog::Compute::ArubaCloud::Server.create, #{message}")
              Fog::Logger.warning(server.inspect)
              sleep(1)
            end
            try += 1
          end
        end

        def get_server_details
          requires :id
          response = service.get_server_details(id)
          new_attributes = response['Value']
          merge_attributes(new_attributes)
        end

        def power_off
          requires :id, :state
          unless state.eql? RUNNING
            raise Fog::ArubaCloud::Errors::VmStatus.new("Cannot poweroff vm in current state: #{state}")
          end
          @service.power_off_vm(id)
        end

        def power_on
          requires :id, :state
          unless state.eql? STOPPED
            raise Fog::ArubaCloud::Errors::VmStatus.new("Cannot poweron vm in current state: #{state}")
          end
          @service.power_on_vm(id)
        end

        def delete
          requires :id
          state == STOPPED ? service.delete_vm(id) : raise(Fog::ArubaCloud::Errors::VmStatus.new(
              "Cannot delete vm in current state: #{state}"
          ))
        end

        def reinitialize
          requires :id, :hypervisor
          state == STOPPED ? service.reinitialize_vm(id) : raise(Fog::ArubaCloud::Errors::VmStatus.new(
              "Cannot reinitialize vm in current state: #{state}"
          ))
        end

      end
    end
  end
end