import { application } from './controllers/application'

import ConfirmationController from './controllers/confirmation_controller'
application.register('confirmation', ConfirmationController)

import HelloController from './controllers/hello_controller'
application.register('hello', HelloController)

import OperatingHourRowController from './controllers/operating_hour_row_controller'
application.register('operating-hour-row', OperatingHourRowController)

import SortableController from './controllers/sortable_controller'
application.register('sortable', SortableController)

console.log('🔥 Controllers loaded!', { application })
