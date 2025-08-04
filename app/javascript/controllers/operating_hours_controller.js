import { Controller } from '@hotwired/stimulus'

// This controller used to handle all the logic for adding, removing, and toggling operating hours.
// This logic has been refactored to use Turbo Streams and server-side rendering,
// following the Hotwire paradigm.
//
// - Adding a period is now a `button_to` that triggers a `create` action.
// - Removing a period is now a `button_to` that triggers a `destroy` action.
// - Toggling a day's status is a `button_to` that triggers a `toggle_day_status` action.
// - Editing a period is handled by the `operating-hour-row-controller`.
//
// This controller is kept for now in case we need to add back any client-side
// interactions that are not easily handled by Turbo Streams.
export default class extends Controller {
  connect() {
    console.log('OperatingHours controller connected (now simplified).')
  }
}