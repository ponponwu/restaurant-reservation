// Entry point for the build script in your package.json
import '@hotwired/turbo-rails'

// Import Stimulus application
import { application } from './controllers/application'

// Import and register controllers
import CalendarController from './controllers/calendar_controller'
application.register('calendar', CalendarController)

import ClosureDatesController from './controllers/closure_dates_controller'
application.register('closure-dates', ClosureDatesController)

import ConfirmationController from './controllers/confirmation_controller'
application.register('confirmation', ConfirmationController)

import ReservationCalendarController from './controllers/reservation_calendar_controller'
application.register('reservation-calendar', ReservationCalendarController)

import RestaurantManagementController from './controllers/restaurant_management_controller'
application.register('restaurant-management', RestaurantManagementController)

import SortableController from './controllers/sortable_controller'
application.register('sortable', SortableController)

import ReservationController from './controllers/reservation_controller'
application.register('reservation', ReservationController)
