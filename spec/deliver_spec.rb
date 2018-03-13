require './lib/tuktuk/tuktuk'
require 'rspec/mocks'

describe 'deliver' do

end

describe 'deliver many' do

  before(:each) do
    @mock_smtp = double('Net::SMTP')
    Net::SMTP.stub(:new).and_return(@mock_smtp)
  end

  describe 'when no emails are passed' do

    it 'raises' do
      lambda do
        Tuktuk.deliver_many []
      end.should raise_error
    end

  end

  describe 'when one email contains multiple addresses' do

    it 'raises' do
      lambda do
        Tuktuk.deliver_many [ email, email(:to => 'one@user.com, two@user.com')]
      end.should raise_error
    end

  end

  describe 'when emails are valid' do

    it 'groups them by domain' do

    end

    describe 'and max_workers is 0' do

      it 'does not start any threads' do

      end

    end

    describe 'and max_workers is >0' do

      it 'does not spawn any more threads than the max allowed' do

      end

    end

    describe 'and max workers is auto' do

      it 'spawns a new thread for each domain' do

      end

    end

    describe 'when delivering to domain' do

      before do
        @mock_smtp.stub(:start).and_yield('foo')
        @emails = [email, email, email]

        @success = double('Net::SMTP::Response')
        @soft_email_bounce  = Tuktuk::SoftBounce.new('503 Sender already specified')
        @hard_email_bounce  = Tuktuk::HardBounce.new('505 Mailbox not found')
        @soft_server_bounce = Tuktuk::SoftBounce.new('Be back in a sec')
        @hard_server_bounce = Tuktuk::HardBounce.new('No MX records found.')
      end

      describe 'when domain exists' do

        before do
          @domain = 'domain.com'
        end

        describe 'and has valid MX servers' do

          before do
            @servers = ['mx1.domain.com', 'mx2.domain.com', 'mx3.domain.com']
            Tuktuk.stub(:smtp_servers_for_domain).and_return(@servers)
          end

          it 'starts by delivering to first one' do
            Tuktuk.should_receive(:send_many_now).once.with('mx1.domain.com', [1]).and_return([[1,'ok']])
            Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', [1])
          end

          describe 'and first server processes all our mail' do

            describe 'and all mail goes through' do

              before do
                @responses = []
                @emails.each { |e| @responses.push [e, @success] }
              end

              it 'does not try to connect to second server' do
                Tuktuk.should_receive(:send_many_now).once.with('mx1.domain.com', @emails).and_return(@responses)
                Tuktuk.should_not_receive(:send_many_now).with('mx2.domain.com')
                Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
              end

            end

            describe 'and all emails were hard failures (bounces)' do

              before do
                @responses = []
                @emails.each { |e| @responses.push [e, @hard_email_bounce] }
              end

              it 'does not try to connect to second server' do
                Tuktuk.should_receive(:send_many_now).once.with('mx1.domain.com', @emails).and_return(@responses)
                Tuktuk.should_not_receive(:send_many_now).with('mx2.domain.com')
                Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
              end

            end

          end

          describe 'and first server is down' do

            before do
              @responses = []
              @emails.each { |e| @responses.push [e, @success] }
            end

            it 'does not raise error' do
              Tuktuk.should_receive(:init_connection).once.with('mx1.domain.com').and_raise('Unable to connect.')
              Tuktuk.should_receive(:init_connection).once.with('mx2.domain.com').and_raise('Unable to connect.')
              Tuktuk.should_receive(:init_connection).once.with('mx3.domain.com').and_raise('Unable to connect.')
              # Tuktuk.should_receive(:init_connection).once.and_raise('Unable to connect.')
              expect do
                Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
              end.not_to raise_error # (RuntimeError)
            end

            it 'returns empty responses' do
              Tuktuk.should_receive(:init_connection).once.with('mx1.domain.com').and_raise('Unable to connect.')
              responses = Tuktuk.send(:send_many_now, 'mx1.domain.com', @emails)
              responses.should be_empty
            end

            it 'tries to connect to second server' do
              Tuktuk.should_receive(:send_many_now).once.with('mx1.domain.com', @emails).and_return([])
              Tuktuk.should_receive(:send_many_now).once.with('mx2.domain.com', @emails).and_return(@responses)
              Tuktuk.should_not_receive(:send_many_now).with('mx3.domain.com')
              Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
            end

          end

          describe 'and first server receives only one email' do

            before do
              @first = [@emails[0], @success]
              @last_two = [[@emails[1], @success], [@emails[2], @soft_email_bounce]]
            end

            it 'does not try to send that same email to second server' do
              Tuktuk.should_receive(:send_many_now).once.with('mx1.domain.com', @emails).and_return([@first])
              last_two_emails = @emails.last(2)
              last_two_emails.include?(@emails.first).should be false
              Tuktuk.should_receive(:send_many_now).once.with('mx2.domain.com', last_two_emails).and_return(@last_two)
              Tuktuk.should_not_receive(:send_many_now).with('mx3.domain.com')
              Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
            end

            describe 'and other servers are down' do

              before do
                # TODO: for some reason the :init_connection on line  138 is affecting this
                # this test should pass when running on its own
                # Tuktuk.should_receive(:init_connection).once.with('mx1.domain.com').and_return(@mock_smtp)
                # Tuktuk.should_receive(:init_connection).once.with('mx2.domain.com').and_raise('Unable to connect.')
                # Tuktuk.should_receive(:init_connection).once.with('mx3.domain.com').and_raise('Unable to connect.')
              end

              it 'should not mark first email as bounced' do
                Tuktuk.should_receive(:send_many_now).and_return([@first], [], [])
                responses = Tuktuk.send(:lookup_and_deliver_by_domain, 'domain.com', @emails)
                responses[1][0].should be_a(Tuktuk::Bounce) if responses[1]
                responses[0][0].should_not be_a(Tuktuk::Bounce)
              end

            end

          end

        end

      end

    end

  end

  def email(attrs = {})
    { :to => "user#{rand(1000)}@domain.com",
      :from => 'me@company.com',
      :subject => 'Test email',
      :body => 'Hello world.'
    }.merge(attrs)
  end

end
