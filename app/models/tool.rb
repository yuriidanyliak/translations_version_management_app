class Tool < ApplicationRecord
    validates :name, :language, presence: true
    validates :json_spec, presence: { message: 'seems to be not on Github repo. Are you sure it was uploaded?' }
end
