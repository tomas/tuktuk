require './lib/tuktuk/tuktuk'

describe 'deliver' do
	
end

describe 'deliver many' do
	
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
		
#		describe 'and max_workers is 0' do
			
#		end
		
#		describe 'and max_workers is >0' do
#			
#		end
		
		describe 'and max workers is auto' do
			
		end
		
		describe 'when sending' do
			
			
			
		end
		
	end
	
	def email(attrs = {})
		{
			:to => 'user@domain.com',
			:from => 'me@company.com',
			:subject => 'Test email',
			:body => 'Hello world.'
		}.merge(attrs)
	end
	
end