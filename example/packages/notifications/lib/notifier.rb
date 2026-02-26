# frozen_string_literal: true

class Notifier
  def self.send_invoice_notification(invoice)
    total = Finance::Invoice === invoice ? invoice.total : invoice
    "📧 Invoice notification sent for #{total}"
  end
end
