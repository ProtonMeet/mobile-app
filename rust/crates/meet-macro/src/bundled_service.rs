use proc_macro::TokenStream;
use proc_macro_error::{abort, emit_error};
use quote::{format_ident, quote};
use syn::{ItemStruct, ItemTrait, Meta};

pub fn bundled_service_inner(item: ItemTrait) -> TokenStream {
    let trait_declaration = quote! {
        #[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
        #[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
        #item
    };

    let trait_vis = item.vis;
    let trait_ident = item.ident;
    let trait_items = item.items;
    let mock_ident = format_ident!("Mock{trait_ident}");

    let mock_declaration = quote! {
        #[cfg(test)]
        mockall::mock! {
            #trait_vis #trait_ident {}

            impl BundledService for #trait_ident {
                fn set_service_bundle(&mut self, bundle: Weak<ServicesBundle>);
                fn services(&self) -> Result<Arc<ServicesBundle>, anyhow::Error>;
            }

            #[async_trait::async_trait]
            impl #trait_ident for #trait_ident {
                #(#trait_items)*
            }
        }
    };

    let factory_declaration = quote! {
        #[cfg(test)]
        impl #mock_ident {
            #trait_vis fn with_bundled_service_setup() -> Self {
                let mut s = Self::new();

                let services = std::sync::Arc::<
                    std::sync::OnceLock<
                        std::sync::Weak<crate::service::services_bundle::ServicesBundle>,
                    >,
                >::default();

                let services_clone = services.clone();
                s.expect_set_service_bundle().returning(move |b| {
                    services_clone.set(b).expect("Attempted to set ServiceBundle multiple times");
                });
                s.expect_services().returning(move || {
                    services
                        .get()
                        .expect("Service bundle never set!")
                        .upgrade()
                        .ok_or_else(|| anyhow::anyhow!("Service bundle is no longer available"))
                });

                s
            }
        }
    };

    quote! {
        #trait_declaration
        #mock_declaration
        #factory_declaration
    }
    .into()
}

pub fn bundled_service_derive_inner(item: ItemStruct) -> TokenStream {
    let bundle_fields = item
        .fields
        .iter()
        .enumerate()
        .filter_map(|(idx, field)| {
            field
                .attrs
                .iter()
                .find(|attr| attr.path().is_ident("service_bundle"))
                .map(|attr| (idx, field, attr))
        })
        .collect::<Vec<_>>();

    if bundle_fields.len() > 1 {
        for (_, _, attribute) in bundle_fields {
            emit_error!(
                attribute,
                "#[service_bundle] is only allowed on a single field"
            );
        }

        return Default::default();
    }

    if bundle_fields.is_empty() {
        abort!(item, "Missing #[service_bundle] on one field")
    }

    let (idx, field, attr) = bundle_fields[0];

    if !matches!(attr.meta, Meta::Path(_)) {
        abort!(attr, "#[service_bundle] does not take any parameters");
    }

    let struct_ident = item.ident;
    let field_ident = field
        .ident
        .clone()
        .unwrap_or_else(|| format_ident!("{idx}"));

    quote! {
        impl crate::service::services_bundle::BundledService for #struct_ident {
            fn set_service_bundle(
                &mut self,
                bundle: std::sync::Weak<crate::service::services_bundle::ServicesBundle>
            ) {
                self.#field_ident = bundle;
            }

            fn services(&self) ->
            Result<
                std::sync::Arc<crate::service::services_bundle::ServicesBundle>,
                anyhow::Error
            > {
                self.#field_ident
                    .upgrade()
                    .ok_or_else(|| anyhow::anyhow!("Service bundle is no longer available"))
            }
        }
    }
    .into()
}
