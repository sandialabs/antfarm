################################################################################
#                                                                              #
# Copyright (2008-2014) Sandia Corporation. Under the terms of Contract        #
# DE-AC04-94AL85000 with Sandia Corporation, the U.S. Government retains       #
# certain rights in this software.                                             #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to     #
# deal in the Software without restriction, including without limitation the   #
# rights to use, copy, modify, merge, publish, distribute, distribute with     #
# modifications, sublicense, and/or sell copies of the Software, and to permit #
# persons to whom the Software is furnished to do so, subject to the following #
# conditions:                                                                  #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# ABOVE COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, #
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR #
# IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE          #
# SOFTWARE.                                                                    #
#                                                                              #
# Except as contained in this notice, the name(s) of the above copyright       #
# holders shall not be used in advertising or otherwise to promote the sale,   #
# use or other dealings in this Software without prior written authorization.  #
#                                                                              #
################################################################################

module Antfarm
  module Models
    class IPIf < ActiveRecord::Base
      attr_accessor :addr # IPAddrExt object so we can track prefix if provided

      belongs_to :l3_if, :inverse_of => :ip_if

      after_create :create_ip_net
      after_create :associate_l3_net

      validates :address, :presence => true
      validates :l3_if,   :presence => true

      # Create the `@addr` instance variable on the record when model is found
      after_find do |record|
        @addr = Antfarm::IPAddrExt.new(record.address)
      end

      # Validate data for requirements before saving interface to the database.
      #
      # Was using validate_on_create, but decided that restraints should occur
      # on anything saved to the database at any time, including a create and an
      # update.
      validates_each :address do |record, attr, value|
        begin
          # This block is run outside of the context of a model instance,
          # so `@addr` cannot be used here. Rather, we must reference it via
          # the attribute accessor `addr` available on the model instance.
          record.addr = Antfarm::IPAddrExt.new(value)
          record.address = record.addr.to_s

          # Don't save the interface if it's a loopback address.
          if record.addr.loopback_address?
            record.errors.add(:address, 'loopback address not allowed')
          end

          # If the address is public and it already exists in the database,
          # don't create a new one but still create a new IP Network just in
          # case the data given for this address includes more detailed
          # information about its network.
          unless record.addr.private_address?
            interface = IPIf.find_by_address(record.address)
            if interface
              # We have to call `create_ip_net` here even though an
              # `after_create` callback exists to call `create_ip_net` because
              # if we're in this block of code then we're adding errors to the
              # record and as such it won't actually be created and callbacks
              # won't be executed.
              record.create_ip_net
              message = "#{record.address} already exists, but a new IP Network was created"
              record.errors.add(:address, message)
              Antfarm.log :info, message
            end
          end
        rescue ArgumentError
          record.errors.add(:address, "Invalid IP address: #{value}")
        end
      end

      def create_ip_net
        # Check to see if a network exists that contains this address.
        # If not, create a small one that does.
        unless L3Net.network_containing(@addr.to_cidr_string)
          if @addr.prefix == 32 # no subnet data provided
            @addr.prefix = Antfarm.config.prefix # defaults to /30

            # address for this interface shouldn't be a network address...
            if @addr == @addr.network
              @addr.prefix = Antfarm.config.prefix - 1
            end

            certainty_factor = Antfarm::CF_LIKELY_FALSE
          else
            certainty_factor = Antfarm::CF_PROVEN_TRUE
          end

          L3Net.create!(
            :certainty_factor => certainty_factor,
            :protocol => 'IP',
            :ip_net_attributes => { :address => @addr.to_cidr_string }
          )
        end
      end

      def associate_l3_net
        if layer3_network = L3Net.network_containing(self.address)
          self.l3_if.update_attribute :l3_net, layer3_network
        end
      end

      # Allow prefix provided to be nil just in case this
      # call is part of a loop that may or may not need
      # to change the prefix. See the `traceroute` plugin
      # for an example use case such as this.
      def self.execute_with_prefix(prefix = nil, &block)
        if prefix.nil?
          yield
        else
          original_prefix = Antfarm.config.prefix
          Antfarm.config.prefix = prefix.to_i
          yield
          Antfarm.config.prefix = original_prefix
        end
      end
    end
  end
end
