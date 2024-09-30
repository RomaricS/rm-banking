import React, { useCallback, useEffect, useState } from 'react';
import { Button } from './ui/button';
import {
    PlaidLinkOnSuccess,
    PlaidLinkOptions,
    usePlaidLink,
} from 'react-plaid-link';
import { useRouter } from 'next/navigation';
import {
    createLinkToken,
    exchangePublicToken,
} from '@/lib/actions/user.actions';
import Image from 'next/image';

const PlaidLink = ({ user, variant }: PlaidLinkProps) => {
    const router = useRouter();
    const [token, setToken] = useState<string>('');

    useEffect(() => {
        const fetchLinkToken = async () => {
            const data = await createLinkToken(user);
            setToken(data?.linkToken);
        };

        fetchLinkToken();
    }, [user]);

    const onSuccess = useCallback<PlaidLinkOnSuccess>(
        async (public_token: string) => {
            await exchangePublicToken({ publicToken: public_token, user });
            router.push('/');
        },
        [user]
    );

    const config: PlaidLinkOptions = {
        token,
        onSuccess,
    };

    const { open, ready } = usePlaidLink(config);

    return (
        <Button
            onClick={() => open()}
            disabled={!ready}
            className={`plaidlink-${variant ?? 'default'}`}>
            {variant !== 'primary' && (
                <Image
                    src='/icons/connect-bank.svg'
                    alt='connect bank'
                    width={24}
                    height={24}
                />
            )}

            {variant !== 'primary' && (
                <p
                    className={`text-[16px] font-semibold text-black-2 ${
                        variant === 'ghost' ? 'hiddenl xl:block' : ''
                    }`}>
                    Connect bank
                </p>
            )}
        </Button>
    );
};

export default PlaidLink;
