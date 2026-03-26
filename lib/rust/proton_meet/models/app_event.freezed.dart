// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppEvent()';
}


}

/// @nodoc
class $AppEventCopyWith<$Res>  {
$AppEventCopyWith(AppEvent _, $Res Function(AppEvent) __);
}


/// Adds pattern-matching-related methods to [AppEvent].
extension AppEventPatterns on AppEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppEvent_UserStateChanged value)?  userStateChanged,TResult Function( AppEvent_ConnectionChanged value)?  connectionChanged,TResult Function( AppEvent_Error value)?  error,TResult Function( AppEvent_MlsGroupUpdated value)?  mlsGroupUpdated,TResult Function( AppEvent_MlsSyncStateChanged value)?  mlsSyncStateChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppEvent_UserStateChanged() when userStateChanged != null:
return userStateChanged(_that);case AppEvent_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that);case AppEvent_Error() when error != null:
return error(_that);case AppEvent_MlsGroupUpdated() when mlsGroupUpdated != null:
return mlsGroupUpdated(_that);case AppEvent_MlsSyncStateChanged() when mlsSyncStateChanged != null:
return mlsSyncStateChanged(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppEvent_UserStateChanged value)  userStateChanged,required TResult Function( AppEvent_ConnectionChanged value)  connectionChanged,required TResult Function( AppEvent_Error value)  error,required TResult Function( AppEvent_MlsGroupUpdated value)  mlsGroupUpdated,required TResult Function( AppEvent_MlsSyncStateChanged value)  mlsSyncStateChanged,}){
final _that = this;
switch (_that) {
case AppEvent_UserStateChanged():
return userStateChanged(_that);case AppEvent_ConnectionChanged():
return connectionChanged(_that);case AppEvent_Error():
return error(_that);case AppEvent_MlsGroupUpdated():
return mlsGroupUpdated(_that);case AppEvent_MlsSyncStateChanged():
return mlsSyncStateChanged(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppEvent_UserStateChanged value)?  userStateChanged,TResult? Function( AppEvent_ConnectionChanged value)?  connectionChanged,TResult? Function( AppEvent_Error value)?  error,TResult? Function( AppEvent_MlsGroupUpdated value)?  mlsGroupUpdated,TResult? Function( AppEvent_MlsSyncStateChanged value)?  mlsSyncStateChanged,}){
final _that = this;
switch (_that) {
case AppEvent_UserStateChanged() when userStateChanged != null:
return userStateChanged(_that);case AppEvent_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that);case AppEvent_Error() when error != null:
return error(_that);case AppEvent_MlsGroupUpdated() when mlsGroupUpdated != null:
return mlsGroupUpdated(_that);case AppEvent_MlsSyncStateChanged() when mlsSyncStateChanged != null:
return mlsSyncStateChanged(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( UserState field0)?  userStateChanged,TResult Function( bool connected)?  connectionChanged,TResult Function( String message)?  error,TResult Function( String roomId,  String key,  BigInt epoch)?  mlsGroupUpdated,TResult Function( MlsSyncState state,  RejoinReason? reason)?  mlsSyncStateChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppEvent_UserStateChanged() when userStateChanged != null:
return userStateChanged(_that.field0);case AppEvent_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that.connected);case AppEvent_Error() when error != null:
return error(_that.message);case AppEvent_MlsGroupUpdated() when mlsGroupUpdated != null:
return mlsGroupUpdated(_that.roomId,_that.key,_that.epoch);case AppEvent_MlsSyncStateChanged() when mlsSyncStateChanged != null:
return mlsSyncStateChanged(_that.state,_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( UserState field0)  userStateChanged,required TResult Function( bool connected)  connectionChanged,required TResult Function( String message)  error,required TResult Function( String roomId,  String key,  BigInt epoch)  mlsGroupUpdated,required TResult Function( MlsSyncState state,  RejoinReason? reason)  mlsSyncStateChanged,}) {final _that = this;
switch (_that) {
case AppEvent_UserStateChanged():
return userStateChanged(_that.field0);case AppEvent_ConnectionChanged():
return connectionChanged(_that.connected);case AppEvent_Error():
return error(_that.message);case AppEvent_MlsGroupUpdated():
return mlsGroupUpdated(_that.roomId,_that.key,_that.epoch);case AppEvent_MlsSyncStateChanged():
return mlsSyncStateChanged(_that.state,_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( UserState field0)?  userStateChanged,TResult? Function( bool connected)?  connectionChanged,TResult? Function( String message)?  error,TResult? Function( String roomId,  String key,  BigInt epoch)?  mlsGroupUpdated,TResult? Function( MlsSyncState state,  RejoinReason? reason)?  mlsSyncStateChanged,}) {final _that = this;
switch (_that) {
case AppEvent_UserStateChanged() when userStateChanged != null:
return userStateChanged(_that.field0);case AppEvent_ConnectionChanged() when connectionChanged != null:
return connectionChanged(_that.connected);case AppEvent_Error() when error != null:
return error(_that.message);case AppEvent_MlsGroupUpdated() when mlsGroupUpdated != null:
return mlsGroupUpdated(_that.roomId,_that.key,_that.epoch);case AppEvent_MlsSyncStateChanged() when mlsSyncStateChanged != null:
return mlsSyncStateChanged(_that.state,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AppEvent_UserStateChanged extends AppEvent {
  const AppEvent_UserStateChanged(this.field0): super._();
  

 final  UserState field0;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppEvent_UserStateChangedCopyWith<AppEvent_UserStateChanged> get copyWith => _$AppEvent_UserStateChangedCopyWithImpl<AppEvent_UserStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent_UserStateChanged&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppEvent.userStateChanged(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppEvent_UserStateChangedCopyWith<$Res> implements $AppEventCopyWith<$Res> {
  factory $AppEvent_UserStateChangedCopyWith(AppEvent_UserStateChanged value, $Res Function(AppEvent_UserStateChanged) _then) = _$AppEvent_UserStateChangedCopyWithImpl;
@useResult
$Res call({
 UserState field0
});




}
/// @nodoc
class _$AppEvent_UserStateChangedCopyWithImpl<$Res>
    implements $AppEvent_UserStateChangedCopyWith<$Res> {
  _$AppEvent_UserStateChangedCopyWithImpl(this._self, this._then);

  final AppEvent_UserStateChanged _self;
  final $Res Function(AppEvent_UserStateChanged) _then;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppEvent_UserStateChanged(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as UserState,
  ));
}


}

/// @nodoc


class AppEvent_ConnectionChanged extends AppEvent {
  const AppEvent_ConnectionChanged({required this.connected}): super._();
  

 final  bool connected;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppEvent_ConnectionChangedCopyWith<AppEvent_ConnectionChanged> get copyWith => _$AppEvent_ConnectionChangedCopyWithImpl<AppEvent_ConnectionChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent_ConnectionChanged&&(identical(other.connected, connected) || other.connected == connected));
}


@override
int get hashCode => Object.hash(runtimeType,connected);

@override
String toString() {
  return 'AppEvent.connectionChanged(connected: $connected)';
}


}

/// @nodoc
abstract mixin class $AppEvent_ConnectionChangedCopyWith<$Res> implements $AppEventCopyWith<$Res> {
  factory $AppEvent_ConnectionChangedCopyWith(AppEvent_ConnectionChanged value, $Res Function(AppEvent_ConnectionChanged) _then) = _$AppEvent_ConnectionChangedCopyWithImpl;
@useResult
$Res call({
 bool connected
});




}
/// @nodoc
class _$AppEvent_ConnectionChangedCopyWithImpl<$Res>
    implements $AppEvent_ConnectionChangedCopyWith<$Res> {
  _$AppEvent_ConnectionChangedCopyWithImpl(this._self, this._then);

  final AppEvent_ConnectionChanged _self;
  final $Res Function(AppEvent_ConnectionChanged) _then;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? connected = null,}) {
  return _then(AppEvent_ConnectionChanged(
connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class AppEvent_Error extends AppEvent {
  const AppEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppEvent_ErrorCopyWith<AppEvent_Error> get copyWith => _$AppEvent_ErrorCopyWithImpl<AppEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'AppEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $AppEvent_ErrorCopyWith<$Res> implements $AppEventCopyWith<$Res> {
  factory $AppEvent_ErrorCopyWith(AppEvent_Error value, $Res Function(AppEvent_Error) _then) = _$AppEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$AppEvent_ErrorCopyWithImpl<$Res>
    implements $AppEvent_ErrorCopyWith<$Res> {
  _$AppEvent_ErrorCopyWithImpl(this._self, this._then);

  final AppEvent_Error _self;
  final $Res Function(AppEvent_Error) _then;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(AppEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppEvent_MlsGroupUpdated extends AppEvent {
  const AppEvent_MlsGroupUpdated({required this.roomId, required this.key, required this.epoch}): super._();
  

 final  String roomId;
 final  String key;
 final  BigInt epoch;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppEvent_MlsGroupUpdatedCopyWith<AppEvent_MlsGroupUpdated> get copyWith => _$AppEvent_MlsGroupUpdatedCopyWithImpl<AppEvent_MlsGroupUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent_MlsGroupUpdated&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.key, key) || other.key == key)&&(identical(other.epoch, epoch) || other.epoch == epoch));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,key,epoch);

@override
String toString() {
  return 'AppEvent.mlsGroupUpdated(roomId: $roomId, key: $key, epoch: $epoch)';
}


}

/// @nodoc
abstract mixin class $AppEvent_MlsGroupUpdatedCopyWith<$Res> implements $AppEventCopyWith<$Res> {
  factory $AppEvent_MlsGroupUpdatedCopyWith(AppEvent_MlsGroupUpdated value, $Res Function(AppEvent_MlsGroupUpdated) _then) = _$AppEvent_MlsGroupUpdatedCopyWithImpl;
@useResult
$Res call({
 String roomId, String key, BigInt epoch
});




}
/// @nodoc
class _$AppEvent_MlsGroupUpdatedCopyWithImpl<$Res>
    implements $AppEvent_MlsGroupUpdatedCopyWith<$Res> {
  _$AppEvent_MlsGroupUpdatedCopyWithImpl(this._self, this._then);

  final AppEvent_MlsGroupUpdated _self;
  final $Res Function(AppEvent_MlsGroupUpdated) _then;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? key = null,Object? epoch = null,}) {
  return _then(AppEvent_MlsGroupUpdated(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,epoch: null == epoch ? _self.epoch : epoch // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class AppEvent_MlsSyncStateChanged extends AppEvent {
  const AppEvent_MlsSyncStateChanged({required this.state, this.reason}): super._();
  

 final  MlsSyncState state;
 final  RejoinReason? reason;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppEvent_MlsSyncStateChangedCopyWith<AppEvent_MlsSyncStateChanged> get copyWith => _$AppEvent_MlsSyncStateChangedCopyWithImpl<AppEvent_MlsSyncStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppEvent_MlsSyncStateChanged&&(identical(other.state, state) || other.state == state)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,state,reason);

@override
String toString() {
  return 'AppEvent.mlsSyncStateChanged(state: $state, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $AppEvent_MlsSyncStateChangedCopyWith<$Res> implements $AppEventCopyWith<$Res> {
  factory $AppEvent_MlsSyncStateChangedCopyWith(AppEvent_MlsSyncStateChanged value, $Res Function(AppEvent_MlsSyncStateChanged) _then) = _$AppEvent_MlsSyncStateChangedCopyWithImpl;
@useResult
$Res call({
 MlsSyncState state, RejoinReason? reason
});




}
/// @nodoc
class _$AppEvent_MlsSyncStateChangedCopyWithImpl<$Res>
    implements $AppEvent_MlsSyncStateChangedCopyWith<$Res> {
  _$AppEvent_MlsSyncStateChangedCopyWithImpl(this._self, this._then);

  final AppEvent_MlsSyncStateChanged _self;
  final $Res Function(AppEvent_MlsSyncStateChanged) _then;

/// Create a copy of AppEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,Object? reason = freezed,}) {
  return _then(AppEvent_MlsSyncStateChanged(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as MlsSyncState,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as RejoinReason?,
  ));
}


}

// dart format on
