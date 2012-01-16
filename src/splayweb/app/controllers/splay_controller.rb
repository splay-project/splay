## Splayweb ### v1.1 ###
## Copyright 2006-2011
## http://www.splay-project.org
## 
## 
## 
## This file is part of Splayd.
## 
## Splayd is free software: you can redistribute it and/or modify 
## it under the terms of the GNU General Public License as published 
## by the Free Software Foundation, either version 3 of the License, 
## or (at your option) any later version.
## 
## Splayd is distributed in the hope that it will be useful,but 
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
## See the GNU General Public License for more details.
## 
## You should have received a copy of the GNU General Public License
## along with Splayd. If not, see <http://www.gnu.org/licenses/>.


class SplayController < ApplicationController
	layout 'default'

  def self.mode
    # local | network | planetlab | ground | live
    "planetlab"
  end

  def self.localization
    if mode() == "planetlab" or mode() == "network"
      true
    else
      false
    end
  end

  def self.google_key
    #"ABQIAAAAXJkkrfQHnoRBN-a4oojlLBRagHNcEDMOS13RVoMUhChp05nuqxT5X9-oWonuac-YM3xdCzFUqGZFjw"
    "ABQIAAAAyOslG_bcOWnKfizrq9BGVBQkVKP3EH14cSNkuq5YO7OSccDxfxQBR45JMZzP4IyHlIVtZ-jlpdqwRg"
  end

  def self.google_urchin
    "UA-2991998-3"
  end

	def index
		@g_splayds = SplaydController::array_for_map
	end
end
