class AddPhoneBookingLimitToReservationPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :reservation_policies, :max_bookings_per_phone, :integer, default: 5, comment: '單一手機號碼在限制期間內的最大訂位次數'
    add_column :reservation_policies, :phone_limit_period_days, :integer, default: 30, comment: '手機號碼訂位限制的期間天數'
  end
end
