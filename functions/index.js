// Firebase Cloud Functions v2 — FCM Push Notifications for PurrSync
// Tier 2 feature: requires Blaze plan. Set kEnablePush = true in main.dart to enable.
// To deploy: firebase deploy --only functions

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

// Notify owner when vet updates their reservation status
exports.onReservationStatusChange = onDocumentUpdated('reservations/{resId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;

  const ownerId = after.ownerId;
  const userDoc = await admin.firestore().collection('users').doc(ownerId).get();
  const fcmToken = userDoc.data()?.fcmToken;
  if (!fcmToken) return;

  const statusLabels = {
    accepted: 'Accepted',
    declined: 'Declined',
    completed: 'Completed',
    cancelled: 'Cancelled',
    expired: 'Expired',
  };
  const label = statusLabels[after.status] || after.status;

  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: `Reservation ${label}`,
      body: `Your reservation with ${after.vetName} for ${after.catName} has been ${label.toLowerCase()}.`,
    },
  });
});

// Notify owner when clinic updates their booking status
exports.onBookingStatusChange = onDocumentUpdated('bookings/{bookId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;

  const ownerId = after.ownerId;
  const userDoc = await admin.firestore().collection('users').doc(ownerId).get();
  const fcmToken = userDoc.data()?.fcmToken;
  if (!fcmToken) return;

  const statusLabels = {
    accepted: 'Accepted',
    declined: 'Declined',
    completed: 'Completed',
    cancelled: 'Cancelled',
    expired: 'Expired',
  };
  const label = statusLabels[after.status] || after.status;

  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: `Booking ${label}`,
      body: `Your booking at ${after.clinicName} for ${after.catName} (${after.serviceName}) has been ${label.toLowerCase()}.`,
    },
  });
});
